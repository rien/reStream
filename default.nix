{
  devShell = pkgs: with pkgs;
  let
    remarkable-toolchain = pkgs.remarkable-toolchain.overrideAttrs (old: {
      # The sysroot contains intentional dangling symlinks (runtime paths like
      # /var/lock -> /run/lock) that fail nixpkgs' noBrokenSymlinks check.
      preFixup = (old.preFixup or "") + ''
        find $out -xtype l -delete
      '';
    });
  in
  mkShell {
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
        shfmt
        lz4
      ];
      CARGO_BUILD_TARGET="armv7-unknown-linux-gnueabihf";
      CARGO_TARGET_ARMV7_UNKNOWN_LINUX_GNUEABIHF_LINKER="${remarkable-toolchain}/sysroots/x86_64-codexsdk-linux/usr/bin/arm-remarkable-linux-gnueabi/arm-remarkable-linux-gnueabi-gcc";
      CARGO_TARGET_ARMV7_UNKNOWN_LINUX_GNUEABIHF_RUSTFLAGS=[
        "-C link-arg=-march=armv7-a"
        "-C link-arg=-marm"
        "-C link-arg=-mfpu=neon"
        "-C link-arg=-mfloat-abi=hard"
        "-C link-arg=-mcpu=cortex-a9"
        "-C link-arg=--sysroot=${remarkable-toolchain}/sysroots/cortexa9hf-neon-remarkable-linux-gnueabi"
      ];
    };
}
