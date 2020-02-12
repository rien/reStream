# reStream

Snappy reMarkable screen sharing over SSH.

## Requirements

On your **host** machine:
- Any POSIX-shell (e.g. bash)
- [zstd](http://www.zstd.net/)
- ffmpeg (with ffplay)
- ssh

On your **reMarkable**:
- zstd (`opkg install zstd`)
- netcat (`opkg install netcat`)
- coreutils-head (`opkg install coreutils-head`)
