{
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-24.11-small";
  };

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
      checks.${system}.module = import ./test.nix { inherit pkgs self; };
      packages.${system}.checkmk-agent = pkgs.callPackage ./package.nix { };
      devShells.${system}.default = pkgs.mkShell {
        buildInputs = [
          pkgs.rpmextract
          pkgs.deadnix
          pkgs.nixfmt-rfc-style
        ];
      };
    };
}
