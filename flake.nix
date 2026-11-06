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
        default = import ./module.nix { package = self.packages.${system}.checkmk-agent; };
      };

      checks.${system} = {
        plugin-packages = import ./test-plugin-packages.nix { inherit pkgs self; };
        docker-plugin = import ./test-docker-plugin.nix { inherit pkgs self; };
        features = import ./test-features.nix { inherit pkgs self; };
        package = import ./test.nix { inherit pkgs self; };
        plugins = import ./test-plugins.nix { inherit self pkgs; };
        plugins-module = import ./test-plugins-module.nix { inherit self pkgs; };
      };

      packages.${system} = rec {
        default = checkmk-agent;
        checkmk-agent = pkgs.callPackage ./package.nix { };
      };

      legacyPackages.${system}.checkmkAgentPlugins = {
        smart-posix = pkgs.callPackage ./plugins/smart-posix.nix {
          inherit (self.packages.${system}.checkmk-agent) src version;
        };
        docker = pkgs.callPackage ./plugins/docker.nix {
          inherit (self.packages.${system}.checkmk-agent) src version;
        };
        nut = pkgs.callPackage ./plugins/nut.nix { };
      };

      devShells.${system}.default = pkgs.mkShell {
        buildInputs = [
          pkgs.deadnix
          pkgs.nixfmt
          pkgs.statix
          pkgs.nix-output-monitor
        ];
      };
    };
}
