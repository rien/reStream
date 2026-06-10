{
  description = "Stream the reMarkable screen to your computer";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
    rust-overlay = {
      url = "github:oxalica/rust-overlay";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, flake-utils, rust-overlay, ... }:
    flake-utils.lib.eachDefaultSystem (system:
    let
      overlays = [
        (import rust-overlay)
        (final: prev: {
          remarkable-toolchain = prev.remarkable-toolchain.overrideAttrs (old: {
            # The sysroot contains intentional dangling symlinks (e.g. /var/lock
            # -> /run/lock) that fail the noBrokenSymlinks check in newer nixpkgs.
            preFixup = (old.preFixup or "") + ''
              find $out -xtype l -delete
            '';
          });
        })
      ];
      pkgs = import nixpkgs { inherit system overlays; };

      version = (pkgs.lib.importTOML ./Cargo.toml).package.version;

      rustToolchain = pkgs.rust-bin.stable.latest.default.override {
        targets = [ "armv7-unknown-linux-gnueabihf" ];
        extensions = [ "rust-src" ];
      };

      sysroot = "${pkgs.remarkable-toolchain}/sysroots/cortexa9hf-neon-remarkable-linux-gnueabi";
      linker = "${pkgs.remarkable-toolchain}/sysroots/x86_64-codexsdk-linux/usr/bin/arm-remarkable-linux-gnueabi/arm-remarkable-linux-gnueabi-gcc";
      cargoEnv = {
        CARGO_BUILD_TARGET = "armv7-unknown-linux-gnueabihf";
        CARGO_TARGET_ARMV7_UNKNOWN_LINUX_GNUEABIHF_LINKER = linker;
        CARGO_TARGET_ARMV7_UNKNOWN_LINUX_GNUEABIHF_RUSTFLAGS = [
          "-C link-arg=-march=armv7-a"
          "-C link-arg=-marm"
          "-C link-arg=-mfpu=neon"
          "-C link-arg=-mfloat-abi=hard"
          "-C link-arg=-mcpu=cortex-a9"
          "-C link-arg=--sysroot=${sysroot}"
        ];
      };

      restream-sh = pkgs.stdenv.mkDerivation {
        pname = "restream-sh";
        inherit version;
        src = ./.;
        nativeBuildInputs = [ pkgs.makeWrapper ];
        dontBuild = true;
        installPhase = ''
          install -m755 -D reStream.sh $out/bin/restream.sh
          wrapProgram $out/bin/restream.sh \
            --prefix PATH : ${pkgs.lib.makeBinPath [ pkgs.lz4 pkgs.ffmpeg-full ]}
        '';
      };

      restream-rs = pkgs.stdenv.mkDerivation ({
        pname = "restream-rs";
        inherit version;
        src = ./.;

        cargoDeps = pkgs.rustPlatform.importCargoLock {
          lockFile = ./Cargo.lock;
        };

        nativeBuildInputs = with pkgs; [
          rustToolchain
          remarkable-toolchain
          rustPlatform.cargoSetupHook
        ];

        buildPhase = "cargo build --release --frozen";

        installPhase = ''
          install -m755 -D target/armv7-unknown-linux-gnueabihf/release/restream $out/bin/restream.rs
        '';
      } // cargoEnv);

      restream-full = pkgs.symlinkJoin {
        name = "restream-full-${version}";
        paths = [ restream-sh restream-rs ];
      };

    in
    {
      devShell = pkgs.mkShell ({
        buildInputs = with pkgs; [
          rustToolchain
          remarkable-toolchain
          openssl.dev
          pkg-config
          cargo-watch
          cargo-limit
          shellcheck
          shfmt
          lz4
        ];
      } // cargoEnv);

      packages = {
        default = restream-full;
        restream-sh = restream-sh;
        restream-rs = restream-rs;
        restream-full = restream-full;
      };
    });
}
