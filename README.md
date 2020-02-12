# reStream

Snappy reMarkable screen sharing over SSH.

## Requirements

On your **host** machine:
- Any POSIX-shell (e.g. bash)
- ffmpeg (with ffplay)
- ssh

On your **reMarkable** it is recommended to install [zstd](https://zstd.net) (`opkg install zstd` if you have [entware](https://github.com/evidlo/remarkable_entware) installed.) to have a smoother experience (sub-second latency). However, if you don't have it installed `reStream` will fall back to `gzip` which is installed by default.


