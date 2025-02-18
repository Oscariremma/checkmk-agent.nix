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
    (
      { ... }:
      {
        name = "";
        nodes.server =
          {
            config,
            pkgs,
            ...
          }:
          {
            imports = [ self.nixosModules.default ];

            services.cmk_agent.enable = true;
            environment.systemPackages = [ config.services.cmk_agent.package ];
          };
        testScript = ''
          start_all()
          assert "inoperational" not in server.succeed("cmk-agent-ctl status")
          server.succeed("cmk-agent-ctl dump")
        '';
      }
    )
  ];
}).config.result
