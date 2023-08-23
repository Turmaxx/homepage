{
  description = "Personal Homepage & Blog | Brook Seyoum";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachDefaultSystem (system: 
      let pkgs = nixpkgs.legacyPackages.${system}; in with pkgs;
      {
        devShells.default = mkShell {
          buildInputs = [
            hugo
          ];
          shellHook = ''
            hugo version
          '';
        };
      }
    );
}
