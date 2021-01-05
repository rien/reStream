# reStream

reMarkable screen sharing over SSH.

[![rm1](https://img.shields.io/badge/rM1-supported-green)](https://remarkable.com/store/remarkable)
[![rm2](https://img.shields.io/badge/rM2-supported-green)](https://remarkable.com/store/remarkable-2)

![A demo of reStream](extra/demo.gif)

## Installation

1. Clone this repository: `git clone https://github.com/rien/reStream`.
2. Install `lz4` on your host with your usual package manager. On Ubuntu,
`apt install liblz4-tool` will do the trick.
3. [Set up an SSH key and add it to the ssh-agent](https://help.github.com/en/github/authenticating-to-github/generating-a-new-ssh-key-and-adding-it-to-the-ssh-agent), then add your key to the reMarkable with `ssh-copy-id root@10.11.99.1`. **Note:** the reMarkable 2 doesn't support `ed25519` keys, those users should generate and `rsa` key.
4. Copy the `restream` executable to the reMarkable and make it executable.
    ```
    # scp restream.arm.static root@10.11.99.1:/home/root/restream
    # ssh root@10.11.99.1 'chmod +x /home/root/restream'
    ```

## Usage

1. Connect your reMarkable with the USB cable.
2. Make sure you can [open an SSH connection](https://remarkablewiki.com/tech/ssh).
3. Run `./reStream.sh`
4. A screen will pop-up on your local machine, with a live view of your reMarkable!

### Options

- `-h --help`: show usage information
- `-p --portrait`: shows the reMarkable screen in portrait mode (default: landscape mode, 90 degrees rotated tot the right)
- `-s --source`: the ssh destination of the reMarkable (default: `root@10.11.99.1`)
- `-o --output`: path of the output where the video should be recorded, as understood by `ffmpeg`; if this is `-`, the video is displayed in a new window and not recorded anywhere (default: `-`)
- `-f --format`: when recording to an output, this option is used to force the encoding format; if this is `-`, `ffmpeg`’s auto format detection based on the file extension is used (default: `-`).
- `-w --webcam`: record to a video4linux2 web cam device. By default the first found web cam is taken, this can be overwritten with `-o`. The video is scaled to 1280x720 to ensure compatibility with MS Teams, Skype for business and other programs which need this specific format. See [video4linux loopback](#video4linux-loopback) for installation instructions.
- `-m --measure`: use `pv` to measure how much data throughput you have (good to experiment with parameters to speed up the pipeline)
- `-t --title`: set a custom window title for the video stream. The default title is "reStream". This option is disabled when using `-o --output`

If you have problems, don't hesitate to [open an issue](https://github.com/rien/reStream/issues/new) or [send me an email](mailto:rien.maertens@posteo.be).

## Requirements

On your **host** machine:
- Any POSIX-shell (e.g. bash)
- ffmpeg (with ffplay)
- ssh
- Video4Linux loopback kernel module if you want to use `--webcam`

On your **reMarkable** you need the `restream` binary (see [installation instructions](#installation)).

### Video4Linux Loopback

To set your remarkable as a webcam we need to be able to fake one. This is where the Video4Linux loopback kernel module comes into play. We need both the dkms and util packages. On Ubuntu you need to install:

```
apt install v4l2loopback-utils v4l2loopback-dkms
```

In some package managers `v4l2loopback-utils` is found in `v4l-utils`.

After installing the module you must enable it with 

```
modprobe v4l2loopback
```

To verify that this worked, execute: 

```
v4l2-ctl --list-devices
```

The result should contain a line with "platform:v4l2loopback".

## Troubleshooting

Steps you can try if the script isn't working:
- [Set up an SSH key](#installation)
- Update `ffmpeg` to version 4.

## Development

If you want to play with the `restream` code, you will have to [install Rust](https://www.rust-lang.org/learn/get-started) and [setup the reMarkable toolchain](https://github.com/canselcik/libremarkable#setting-up-the-toolchain) to do cross-platform development.
