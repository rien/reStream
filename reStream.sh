#!/bin/sh
ssh_host="mohowzeg.usb"
landscape=true

width=1408
height=1872
bytes_per_pixel=2
loop_wait="true"
loglevel="info"


if ! ssh "$ssh_host" true; then
    echo "$ssh_host unreachable"
    exit 1
fi

# Gracefully degrade to gzip if zstd is not present
if ssh "$ssh_host" "[ -f /opt/bin/zstd ]"; then
    compress="/opt/bin/zstd"
    decompress="zstd -d"
else
    compress="gzip"
    decompress="gzip -d"
fi


window_bytes="$(($width*$height*$bytes_per_pixel))"
orientation_param="$($landscape && echo '-vf transpose=1')"
head_fb0="dd if=/dev/fb0 count=1 bs=$window_bytes 2>/dev/null"
read_loop="while $head_fb0; do $loop_wait; done | $compress"


set -e

ssh  "$ssh_host" "$read_loop" \
    | $decompress \
    | ffplay -vcodec rawvideo \
             -loglevel "$loglevel" \
             -f rawvideo \
             -pixel_format gray16le \
             -video_size "$width,$height" \
             $landscape_param \
             -i -

