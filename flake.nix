{
  description = "Personal Homepage & Blog | Brook Seyoum";

  inputs.nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";

  outputs = { self, nixpkgs }:
    let
      system = "x86_64-linux";
      # system = "x86_64-darwin;"
      pkgs = nixpkgs.legacyPackages.${system};
    in
    {
      devShells.${system}.default =
        pkgs.mkShell
          {
            buildInputs = with pkgs; [
              hugo
            ];
            shellHook = ''
              hugo version
            '';
          };
      app.serve.program = "${pkgs.writeShellScript "serve" ''
        make serve
      ''}";
    };
}
