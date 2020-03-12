# reStream

reMarkable screen sharing over SSH.

![A demo of reStream](extra/demo.gif)

## Usage

1. Connect your reMarkable with the USB cable.
2. Make sure you can [open an SSH connection](https://remarkablewiki.com/tech/ssh).
3. Run `./reStream.sh`.
4. If you don't have `zstd` installed, it will ask you to copy it. You can answer no, and it will fall back to gzip (which will be slower).
5. A screen will pop-up on your local machine, with a live view of your reMarkable!

If you have problems, don't hesitate to [open an issue](https://github.com/rien/reStream/issues/new) or [send me an email](mailto:rien.maertens@posteo.be).

## Requirements

On your **host** machine:
- Any POSIX-shell (e.g. bash)
- ffmpeg (with ffplay)
- ssh

On your **reMarkable** nothing is needed, unless you want...

### Sub-second latency

To achieve sub-second latency, you'll need [zstd](https://zstd.net) on your
host and on your reMarkable. 

You can install `zstd` on your host with your usual package manager. On Ubuntu,
`apt install zstd` will work.

On your **reMarkable** you can do `opkg install zstd` if you have [entware](https://github.com/evidlo/remarkable_entware) installed. If you don't you can use the binary provided in this repository. In general you shouldn't trust binaries strangers on the internet provide to you, but I provide the option if you don't want the hassle of installing entware.

You can copy the binary to your remarkable with `scp zstd.arm root@10.11.99.1:~/zstd`.

