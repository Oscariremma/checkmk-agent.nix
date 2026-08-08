{ pkgs, self }:
let
  inherit (pkgs) lib;
  # this imports the nixos library that contains our testing framework
  nixos-lib = import (pkgs.path + "/nixos/lib") { };
in
(nixos-lib.runTest {
  hostPkgs = pkgs;
  # This speeds up the evaluation by skipping evaluating documentation (optional)
  defaults.documentation.enable = lib.mkDefault false;
  # This makes `self` available in the NixOS configuration of our virtual machines.
  # This is useful for referencing modules or packages from your own flake
  # as well as importing from other flakes.
  imports = [
    (_: {
      name = "checkmk-agent";
      nodes.server =
        { config, ... }:
        {
          imports = [ self.nixosModules.default ];

          services.checkmk-agent.enable = true;
          environment.systemPackages = [ config.services.checkmk-agent.package ];
        };
      testScript = ''
        start_all()
        assert "inoperational" not in server.succeed("cmk-agent-ctl status")
        dump = server.succeed("cmk-agent-ctl dump")
        assert "<<<check_mk>>>" in dump, "dump output is missing <<<check_mk>>> marker"
      '';
    })
  ];
}).config.result
