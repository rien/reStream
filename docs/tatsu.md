# reMarkable Paper Pure (Tatsu) Support

## Device Overview

| Property | Value |
|---|---|
| Product name | reMarkable Paper Pure |
| Internal codename | Tatsu |
| SoC | NXP i.MX 93 (aarch64, ARM Cortex-A55) |
| Kernel machine string | `reMarkable Tatsu` |
| OS version location | `/etc/os-release` → `IMG_VERSION` |
| Confirmed working on | firmware 3.28.0.172 |

## Display Hardware

| Property | Value |
|---|---|
| Panel | E Ink Carta™ 1300 |
| Physical resolution | 1872 × 1404 (landscape) |
| DRM driver | `eink-carta-panel` |
| DRM mode | 260×1408 (waveform output, not pixels) |

The display is driven via DRM/KMS through `/dev/dri/card0`. The DRM mode
(260×1408) is the packed E Ink waveform output size, not the pixel resolution.

## How It Works

xochitl renders the UI into a **BGRA color buffer** in its own heap memory. This
is the same buffer its built-in screen share feature reads from. reStream reads
directly from this buffer via `/proc/<pid>/mem`.

### Finding the buffer

The buffer is located by scanning `/proc/<xochitl_pid>/maps` for the first
anonymous `rw-p` mapping of 10–16 MB that appears immediately after the last
`/dev/dri/card0` entry. This is reliable across restarts as long as the firmware
version does not change.

### Buffer layout

The buffer stores the display content in **portrait orientation** (1404×1872),
regardless of how the device is held. The landscape content is rotated 90° CCW
into the portrait frame by xochitl.

| Property | Value |
|---|---|
| Pixel format | BGRA (4 bytes/pixel) |
| Frame dimensions | 1404 × 1872 pixels |
| Stride | 1404 × 4 = 5616 bytes/row |
| Frame size | 1404 × 1872 × 4 = 10,513,152 bytes |

### Skip offset

The buffer contains a transparent (alpha=0) region before the visible content.
The skip offset is deliberately **non-row-aligned** so that reading wraps a fixed
number of columns into the next row, achieving a circular horizontal shift that
aligns the left edge of the canvas with the start of the output frame. This is
the same technique used for rM2.

```
skip = 468 blank rows × 5616 bytes/row + 340 transparent columns × 4 bytes
     = 2,628,288 + 1,360
     = 2,629,648 bytes
```

The 340-column offset was confirmed by dumping the first row of content and
finding the first opaque pixel (`00 00 00 ff`) at byte offset 1360.

## reStream.sh Parameters

```sh
"reMarkable Tatsu")
    width=1404
    height=1872
    bytes_per_pixel=4
    fb_file=":mem:"
    pixel_format="bgra"
    skip_offset=2629648
    dark_mode=false
    if $landscape; then
        extra_video_filters="transpose=2"
    fi
    landscape=false
    ;;
```

`transpose=2` (90° CCW) rotates the portrait buffer back to landscape.
Use `-p` to stream in portrait orientation without any rotation.

Note: `transpose=1` (the rM2 default via `landscape=true`) produces an
upside-down result on Tatsu — use `transpose=2` instead.

## Building

The binary must be built for `aarch64` (the Tatsu has no 32-bit compatibility):

```sh
cross build --release --target=aarch64-unknown-linux-musl
scp target/aarch64-unknown-linux-musl/release/restream root@10.11.99.1:~/restream
```

The `--features cursor` build flag is **not supported** on Tatsu — it requires
`libremarkable` which is armhf-only.

## DRM PRIME (investigated, not viable)

DRM PRIME is a mechanism for sharing GPU memory buffers between processes via
file descriptors. On Tatsu, xochitl holds 17 GEM buffer handles for the E Ink
waveform pipeline. We investigated exporting these via `pidfd_getfd()` +
`DRM_IOCTL_PRIME_HANDLE_TO_FD`, but all 17 buffers contain E Ink waveform data
(electrical pulse sequences for the panel), not pixel data. The pixel data lives
in an anonymous heap mapping which PRIME cannot export.
