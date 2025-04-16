# old shell
{
  pkgs ? import <nixpkgs> { config.allowUnfree = true; },
}:
pkgs.mkShell {
  buildInputs = with pkgs; [ hugo ];
  shellHook = ''
    hugo version
  '';
}
