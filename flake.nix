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
        module = import ./test.nix { inherit pkgs self; };
        package-module = import ./test-module.nix { inherit pkgs self; };
        plugins = import ./test2.nix { inherit self pkgs; };
        plugins-module = import ./test2-module.nix { inherit self pkgs; };
      };

      packages.${system} = rec {
        default = checkmk-agent;
        checkmk-agent = pkgs.callPackage ./package.nix { };
        checkmk-agent-from-source = pkgs.callPackage ./package-rust.nix { };
        checkmk-agent-no-plugins = pkgs.callPackage ./package-rust-no-plugins.nix { };
      };

      devShells.${system}.default = pkgs.mkShell {
        buildInputs = [
          pkgs.rpmextract
          pkgs.deadnix
          pkgs.nixfmt
          pkgs.statix
        ];
      };
    };
}
