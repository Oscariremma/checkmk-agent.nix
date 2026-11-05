{ pkgs, self }:
let
  inherit (pkgs) lib;
  nixos-lib = import (pkgs.path + "/nixos/lib") { };

  plugin = pkgs.writeShellScriptBin "test-plugin" ''
    echo '<<<test_plugin>>>'
    echo 'synchronous plugin'
  '';
  asyncPlugin = pkgs.writeShellScriptBin "test-async-plugin" ''
    echo '<<<test_async_plugin>>>'
    echo 'asynchronous plugin'
  '';
  local = pkgs.writeShellScriptBin "test-local" ''
    echo '0 "test_local" - synchronous local check'
  '';
  asyncLocal = pkgs.writeShellScriptBin "test-async-local" ''
    echo '0 "test_async_local" - asynchronous local check'
  '';
in
(nixos-lib.runTest {
  hostPkgs = pkgs;
  defaults.documentation.enable = lib.mkDefault false;
  name = "checkmk-agent-plugins-module";

  nodes.server =
    { config, ... }:
    {
      imports = [ self.nixosModules.default ];

      services.checkmk-agent = {
        enable = true;
        plugins = [ plugin ];
        plugins-async = [
          {
            interval = 2;
            package = asyncPlugin;
          }
        ];
        local = [ local ];
        local-async = [
          {
            interval = 2;
            package = asyncLocal;
          }
        ];
      };
      environment.systemPackages = [ config.services.checkmk-agent.package ];
      environment.etc."checkmk-test.json".text = builtins.toJSON {
        package = toString config.services.checkmk-agent.package;
        controller = toString config.services.checkmk-agent.package.cmk-agent-ctl;
        checks = toString config.services.checkmk-agent.package.agentLibDir;
      };

      specialisation = {
        changed-interval.configuration.services.checkmk-agent = {
          plugins-async = lib.mkForce [
            {
              interval = 3;
              package = asyncPlugin;
            }
          ];
          local-async = lib.mkForce [
            {
              interval = 3;
              package = asyncLocal;
            }
          ];
        };
        without-checks.configuration.services.checkmk-agent = {
          plugins = lib.mkForce [ ];
          plugins-async = lib.mkForce [ ];
          local = lib.mkForce [ ];
          local-async = lib.mkForce [ ];
        };
      };
    };

  testScript = ''
    import json

    def configuration():
        return json.loads(server.succeed("cat /etc/checkmk-test.json"))

    def check_layout(interval):
        root = configuration()["checks"]
        assert root.startswith("/nix/store/")
        server.succeed("test ! -e /var/lib/check_mk_agent/lib && test ! -L /var/lib/check_mk_agent/lib")
        for directory, sync_name, async_name in [
            ("plugins", "test-plugin", "test-async-plugin"),
            ("local", "test-local", "test-async-local"),
        ]:
            path = f"{root}/{directory}"
            server.succeed(f"test -x {path}/{sync_name} && test -x {path}/{interval}/{async_name}")
            server.succeed(f"runuser -u cmk-agent -- test -x {path}/{interval}/{async_name}")
        return root

    start_all()
    server.wait_for_unit("multi-user.target")
    server.wait_for_unit("check-mk-agent.socket")
    server.wait_for_unit("cmk-agent-ctl-daemon.service")
    base_system = server.succeed("readlink -f /run/current-system").strip()
    initial = configuration()
    check_layout(2)

    assert "inoperational" not in server.succeed("cmk-agent-ctl status")
    server.wait_until_succeeds("cmk-agent-ctl dump | grep -F '<<<test_async_plugin'")
    server.wait_until_succeeds("cmk-agent-ctl dump | grep -F 'asynchronous local check'")
    dump = server.succeed("cmk-agent-ctl dump")
    assert "<<<check_mk>>>" in dump
    assert "<<<test_plugin>>>" in dump
    assert '0 "test_local" - synchronous local check' in dump
    assert f"PluginsDirectory: {initial['checks']}/plugins" in dump
    assert f"LocalDirectory: {initial['checks']}/local" in dump

    server.succeed(f"{base_system}/specialisation/changed-interval/bin/switch-to-configuration test")
    changed_root = check_layout(3)
    assert configuration()["package"] != initial["package"]
    assert configuration()["controller"] == initial["controller"]
    for directory in ["plugins", "local"]:
        server.succeed(f"test ! -e {changed_root}/{directory}/2")
    dump = server.succeed("cmk-agent-ctl dump")
    assert f"PluginsDirectory: {changed_root}/plugins" in dump
    assert f"LocalDirectory: {changed_root}/local" in dump

    server.succeed(f"{base_system}/specialisation/without-checks/bin/switch-to-configuration test")
    empty = configuration()
    assert empty["package"] != initial["package"]
    assert empty["controller"] == initial["controller"]
    for directory in ["plugins", "local"]:
        server.succeed(f"test -d {empty['checks']}/{directory} && test -z \"$(ls -A {empty['checks']}/{directory}/)\"")
    dump = server.succeed("cmk-agent-ctl dump")
    assert "<<<test_plugin>>>" not in dump
    assert "<<<test_async_plugin" not in dump
    assert '"test_local"' not in dump
    assert '"test_async_local"' not in dump
    server.succeed("test ! -e /var/lib/check_mk_agent/lib && test ! -L /var/lib/check_mk_agent/lib")

    server.succeed(f"{base_system}/bin/switch-to-configuration test")
    assert configuration() == initial
    check_layout(2)
  '';
}).config.result
