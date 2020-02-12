#!/bin/sh
set -eo pipefail

ssh_host="mohowzeg.usb"
landscape=true

bin_head="/opt/bin/head"
bin_zstd="/opt/bin/zstd"
bin_ncat="/opt/bin/netcat"
width=1408
height=1872
bytes_per_pixel=2

if ! ssh "$ssh_host" true; then
    echo "$ssh_host unreachable"
    exit 1
fi

for prog in $bin_head $bin_zstd $bin_ncat; do
    if ! ssh "$ssh_host" "[ -f $prog ]"; then
        echo "Program $prog is not present on $ssh_host."
        exit 1
    fi
done


window_bytes="$(($width*$height*$bytes_per_pixel))"
landscape_param="$($landscape && echo '-vf transpose=1')"
read_loop="while $bin_head -c $window_bytes /dev/fb0; do sleep .03; done | $bin_zstd"

ssh  "$ssh_host" "$read_loop" \
    | zstd -d \
    | pv - \
    | ffplay -vcodec rawvideo \
             -loglevel error \
             -f rawvideo \
             -pixel_format gray16le \
             -video_size "$width,$height" \
             $landscape_param \
             -i -
