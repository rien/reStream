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
  in
  with pkgs;
  {
    devShell = mkShell {
      buildInputs = [
        remarkable-toolchain
        (rust-bin.stable.latest.default.override {
          targets = [ "armv7-unknown-linux-gnueabihf" ];
          extensions = [ "rust-src" ];
        })
        openssl.dev
        pkg-config
        cargo-watch
        cargo-limit
        shellcheck
        lz4
      ];
      CARGO_BUILD_TARGET="armv7-unknown-linux-gnueabihf";
      CARGO_TARGET_ARMV7_UNKNOWN_LINUX_GNUEABIHF_LINKER="${pkgs.remarkable-toolchain}/sysroots/x86_64-codexsdk-linux/usr/bin/arm-remarkable-linux-gnueabi/arm-remarkable-linux-gnueabi-gcc";
      CARGO_TARGET_ARMV7_UNKNOWN_LINUX_GNUEABIHF_RUSTFLAGS=[
        "-C link-arg=-march=armv7-a"
        "-C link-arg=-marm"
        "-C link-arg=-mfpu=neon"
        "-C link-arg=-mfloat-abi=hard"
        "-C link-arg=-mcpu=cortex-a9"
        "-C link-arg=--sysroot=${pkgs.remarkable-toolchain}/sysroots/cortexa9hf-neon-remarkable-linux-gnueabi"
      ];
    };
  });
}
