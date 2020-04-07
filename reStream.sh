#!/bin/sh

# default values for arguments
ssh_host="root@10.11.99.1" # remarkable connected through USB
landscape=true             # rotate 90 degrees to the right
output_path=-              # display output through ffplay
format=-                   # automatic output format

# loop through arguments and process them
while [ $# -gt 0 ]; do
    case "$1" in
        -p | --portrait)
            landscape=false
            shift
            ;;
        -s | --source)
            ssh_host="$2"
            shift
            shift
            ;;
        -o | --output)
            output_path="$2"
            shift
            shift
            ;;
        -f | --format)
            format="$2"
            shift
            shift
            ;;
        -h | --help | *)
            echo "Usage: $0 [-p] [-s <source>] [-o <output>] [-f <format>]"
            echo "Examples:"
            echo "	$0                              # live view in landscape"
            echo "	$0 -p                           # live view in portrait"
            echo "	$0 -s 192.168.0.10              # connect to different IP"
            echo "	$0 -o remarkable.mp4            # record to a file"
            echo "	$0 -o udp://dest:1234 -f mpegts # record to a stream"
            exit 1
            ;;
    esac
done

# technical parameters
width=1408
height=1872
bytes_per_pixel=2
loop_wait="true"
loglevel="info"

ssh_cmd() {
    ssh -o ConnectTimeout=1 "$ssh_host" "$@"
}

# check if we are able to reach the remarkable
if ! ssh_cmd true; then
    echo "$ssh_host unreachable"
    exit 1
fi

fallback_to_gzip() {
    echo "Falling back to gzip, your experience may not be optimal."
    echo "Go to https://github.com/rien/reStream/#sub-second-latency for a better experience."
    compress="gzip"
    decompress="gzip -d"
    sleep 2
}

# check if lz4 is present on remarkable
if ssh_cmd "[ -f /opt/bin/lz4 ]"; then
    compress="/opt/bin/lz4"
elif ssh_cmd "[ -f ~/lz4 ]"; then
    compress="\$HOME/lz4"
fi

# gracefully degrade to gzip if is not present on remarkable or host
if [ -z "$compress" ]; then
    echo "Your remarkable does not have lz4."
    fallback_to_gzip
elif ! lz4 -V; then
    echo "Your host does not have lz4."
    fallback_to_gzip
else
    decompress="lz4 -d"
fi

# list of ffmpeg filters to apply
video_filters=""

# store extra ffmpeg arguments in $@
set --

# calculate how much bytes the window is
window_bytes="$((width * height * bytes_per_pixel))"

# rotate 90 degrees if landscape=true
$landscape && video_filters="$video_filters,transpose=1"

# set each frame presentation time to the time it is received
video_filters="$video_filters,setpts=(RTCTIME - RTCSTART) / (TB * 1000000)"

# read the first $window_bytes of the framebuffer
head_fb0="dd if=/dev/fb0 count=1 bs=$window_bytes 2>/dev/null"

# loop that keeps on reading and compressing, to be executed remotely
read_loop="while $head_fb0; do $loop_wait; done | $compress"

set -- "$@" -vf "${video_filters#,}"

if [ "$output_path" = - ]; then
    output_cmd=ffplay
else
    output_cmd=ffmpeg

    if [ "$format" != - ]; then
        set -- "$@" -f "$format"
    fi

    set -- "$@" "$output_path"
fi

set -e # stop if an error occurs

# shellcheck disable=SC2086
ssh_cmd "$read_loop" \
    | $decompress \
    | "$output_cmd" \
        -vcodec rawvideo \
        -loglevel "$loglevel" \
        -f rawvideo \
        -pixel_format gray16le \
        -video_size "$width,$height" \
        -i - \
        "$@"
