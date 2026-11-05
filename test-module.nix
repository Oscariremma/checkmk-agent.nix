{ pkgs, self }:
let
  inherit (pkgs) lib;
  nixos-lib = import (pkgs.path + "/nixos/lib") { };
in
(nixos-lib.runTest {
  hostPkgs = pkgs;
  defaults.documentation.enable = lib.mkDefault false;
  name = "checkmk-agent-rpm-module";

  nodes.server = { config, pkgs, ... }: {
    imports = [ self.nixosModules.default ];
    services.checkmk-agent = {
      enable = true;
      asyncLoopInterval = 2;
      package = self.packages.${pkgs.stdenv.hostPlatform.system}.checkmk-agent;
      plugins = [ (pkgs.writeShellScriptBin "rpm-plugin" "echo '<<<rpm_plugin>>>'") ];
      local = [
        (pkgs.writeShellScriptBin "rpm-local" ''echo '0 "rpm_local" - synchronous local check' '')
      ];
      plugins-async = [
        {
          interval = 2;
          package = pkgs.writeShellScriptBin "rpm-async-plugin" "echo '<<<rpm_async_plugin>>>'";
        }
      ];
      local-async = [
        {
          interval = 2;
          package = pkgs.writeShellScriptBin "rpm-async-local" ''echo '0 "rpm_async_local" - asynchronous local check' '';
        }
      ];
    };
    environment.systemPackages = [ config.services.checkmk-agent.package ];
    environment.etc."checkmk-test-root".text =
      toString config.services.checkmk-agent.package.agentLibDir;
  };

  testScript = ''
    import re

    start_all()
    server.wait_for_unit("multi-user.target")
    server.wait_for_unit("check-mk-agent.socket")
    server.wait_for_unit("cmk-agent-ctl-daemon.service")
    server.wait_for_unit("check-mk-agent-async.service")
    root = server.succeed("cat /etc/checkmk-test-root").strip()
    server.succeed(f"test -x {root}/plugins/2/rpm-async-plugin && test -x {root}/local/2/rpm-async-local")
    server.wait_until_succeeds(
        "cmk-agent-ctl dump > /tmp/checkmk-dump && "
        "grep -q '^<<<rpm_async_plugin:cached(' /tmp/checkmk-dump && "
        "grep -q '^cached.*rpm_async_local.*asynchronous local check$' /tmp/checkmk-dump"
    )
    dump = server.succeed("cat /tmp/checkmk-dump")
    assert re.search(r"(?m)^<<<rpm_async_plugin:cached\(\d+,2\)>>>$", dump)
    assert re.search(r'(?m)^cached\(\d+,2\) 0 "rpm_async_local" - asynchronous local check$', dump)
    for name in ["plugins_rpm-async-plugin", "local_rpm-async-local"]:
        cache = f"/var/lib/check_mk_agent/cache/{name}.cache"
        previous = server.succeed(f"stat -c %Y {cache}").strip()
        server.wait_until_succeeds(f'test "$(stat -c %Y {cache})" -gt {previous}', timeout=30)
    assert "<<<check_mk>>>" in dump
    assert "<<<rpm_plugin>>>" in dump
    assert '0 "rpm_local" - synchronous local check' in dump
  '';
}).config.result
