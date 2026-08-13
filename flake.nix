{
  inputs.nixpkgs.url = "github:nixos/nixpkgs/nixos-26.05";

  outputs =
    {
      self,
      nixpkgs,
    }:
    let
      system = "x86_64-linux";
      pkgs = nixpkgs.legacyPackages.${system};
    in
    {
      nixosModules = {
        default = import ./module.nix { package = self.packages.${system}.checkmk-agent-from-source; };
        plugins = import ./module-plugins.nix {
          package = self.packages.${system}.checkmk-agent-no-plugins;
        };
      };

      checks.${system} = {
        package = import ./test.nix { inherit pkgs self; };
        package-module = import ./test-module.nix { inherit pkgs self; };
        plugins = import ./test-plugins.nix { inherit self pkgs; };
        plugins-module = import ./test-plugins-module.nix { inherit self pkgs; };
      };

      packages.${system} = rec {
        default = checkmk-agent;
        checkmk-agent = pkgs.callPackage ./package.nix { };
        checkmk-agent-from-source = pkgs.callPackage ./package-rust.nix { };
        checkmk-agent-check-w-plugins = pkgs.callPackage ./package-rust-check.nix {
          plugins = [
            {
              interval = 1;
              package = pkgs.writeShellApplication {
                name = "smart";
                runtimeInputs = [ pkgs.smartmontools ];
                text = builtins.readFile "${
                  self.packages.${pkgs.stdenv.hostPlatform.system}.checkmk-agent-from-source.src
                }/agents/plugins/smart";
                bashOptions = [ "errexit" ];
              };
            }
            (pkgs.writeShellApplication {
              name = "netstat";
              runtimeInputs = [ pkgs.unixtools.netstat ];
              text = builtins.readFile "${
                self.packages.${pkgs.stdenv.hostPlatform.system}.checkmk-agent-from-source.src
              }/agents/plugins/netstat.linux";
              bashOptions = [ "errexit" ];
            })
          ];
        };
        checkmk-agent-no-plugins = pkgs.callPackage ./package-rust-no-plugins.nix { };
      };

      devShells.${system}.default = pkgs.mkShell {
        buildInputs = [
          pkgs.rpmextract
          pkgs.deadnix
          pkgs.nixfmt
          pkgs.statix
          pkgs.nix-output-monitor
        ];
      };
    };
}
