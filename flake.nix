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
      nixosModules.default = import ./module.nix { package = self.packages.${system}.checkmk-agent; };
      checks.${system} = {
        module = import ./test.nix { inherit pkgs self; };
        plugins = import ./test2.nix { inherit self pkgs; };
      };

      packages.${system} = rec {
        default = checkmk-agent;
        checkmk-agent = pkgs.callPackage ./package.nix { };
        checkmk-agent-from-source = pkgs.callPackage ./package-rust.nix { };
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
