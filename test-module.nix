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
    start_all()
    server.wait_for_unit("multi-user.target")
    server.wait_for_unit("check-mk-agent.socket")
    server.wait_for_unit("cmk-agent-ctl-daemon.service")
    root = server.succeed("cat /etc/checkmk-test-root").strip()
    server.succeed(f"test -x {root}/plugins/2/rpm-async-plugin && test -x {root}/local/2/rpm-async-local")
    dump = server.succeed("cmk-agent-ctl dump")
    assert "<<<check_mk>>>" in dump
    assert "<<<rpm_plugin>>>" in dump
    assert '0 "rpm_local" - synchronous local check' in dump
  '';
}).config.result
