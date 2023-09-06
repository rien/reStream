{
  devShell = pkgs: with pkgs; mkShell {
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
        ffmpeg_6-full
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
}
