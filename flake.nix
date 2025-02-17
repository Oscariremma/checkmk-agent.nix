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
      nixosModules = { };
      packages.${system}.checkmk-agent = pkgs.callPackage ./package.nix { useZibint = false; };
      devShells.${system}.default = pkgs.mkShell {
        buildInputs = [ pkgs.dpkg ];
      };
    };
}
