{
  description = "Stream the reMarkable screen to your computer";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
    rust-overlay = {
      url = "github:oxalica/rust-overlay";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.flake-utils.follows = "flake-utils";
    };
  };
  outputs = {self,  nixpkgs, flake-utils, rust-overlay, ... }:
  flake-utils.lib.eachDefaultSystem (system:
  let
    overlays = [ (import rust-overlay) ];
    pkgs = import nixpkgs {
      inherit system overlays;
    };
    restream-bin = pkgs.stdenv.mkDerivation {
      name = "restream";
      version = (pkgs.lib.importTOML ./Cargo.toml).package.version;
      src = ./.;
      nativeBuildInputs = [ pkgs.makeWrapper pkgs.lz4 pkgs.ffmpeg-full ];
      buildInputs = [ pkgs.lz4 ];

      installPhase = ''
        install -m755 -D reStream.sh $out/bin/restream
        wrapProgram $out/bin/restream --prefix PATH : ${pkgs.lib.makeBinPath [pkgs.lz4 pkgs.ffmpeg-full]}
      '';
    };
  in
  with pkgs;
  {
    devShell = (import ./default.nix).devShell pkgs;
    packages.default = restream-bin;
  });
}
