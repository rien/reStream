#!/bin/sh

# default values for arguments
ssh_host="root@10.11.99.1" # remarkable connected through USB
landscape=true             # rotate 90 degrees to the right
output_path=-              # display output through ffplay
format=-                   # automatic output format

# loop through arguments and process them
while [ $# -gt 0 ]; do
    case "$1" in
        -p|--portrait)
            landscape=false
            shift
            ;;
        -s|--source)
            ssh_host="$2"
            shift
            shift
            ;;
        -o|--output)
            output_path="$2"
            shift
            shift
            ;;
        -f|--format)
            format="$2"
            shift
            shift
            ;;
        *)
            echo "Usage: $0 [-p] [-s <source>] [-o <output>] [-f <format>]"
            exit 1
    esac
done

# technical parameters
width=1408
height=1872
bytes_per_pixel=2
loop_wait="true"
loglevel="info"
ssh_cmd="ssh -o ConnectTimeout=1 "$ssh_host""

# check if we are able to reach the remarkable
if ! $ssh_cmd true; then
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
if $ssh_cmd "[ -f /opt/bin/lz4 ]"; then
    compress="/opt/bin/lz4"
elif $ssh_cmd "[ -f ~/lz4 ]"; then
    compress="~/lz4"
fi

# gracefully degrade to gzip if is not present on remarkable or host
if [ -z "$compress" ]; then
    echo "Your remarkable does not have lz4."
    fallback_to_gzip
elif ! which lz4; then
    echo "Your host does not have lz4."
    fallback_to_gzip
else
    decompress="lz4 -d"
fi




output_args=()
video_filters=()

# calculate how much bytes the window is
window_bytes="$(($width*$height*$bytes_per_pixel))"

# rotate 90 degrees if landscape=true
$landscape && video_filters+=('transpose=1')

# read the first $window_bytes of the framebuffer
head_fb0="dd if=/dev/fb0 count=1 bs=$window_bytes 2>/dev/null"

# loop that keeps on reading and compressing, to be executed remotely
read_loop="while $head_fb0; do $loop_wait; done | $compress"

if [ "$output_path" = - ]; then
    output_command=ffplay
else
    output_command=ffmpeg

    if [ "$format" != - ]; then
        output_args+=('-f' "$format")
    fi

    output_args+=("$output_path")
fi

# set frame presentation time to the time it was received
video_filters+=('setpts=(RTCTIME - RTCSTART) / (TB * 1000000)')

joined_filters=$(IFS=,; echo "${video_filters[*]}")
output_args+=('-vf' "$joined_filters")

set -e # stop if an error occurs

$ssh_cmd "$read_loop" \
    | $decompress \
    | "$output_command" \
             -vcodec rawvideo \
             -loglevel "$loglevel" \
             -f rawvideo \
             -pixel_format gray16le \
             -video_size "$width,$height" \
             -i - \
             "${output_args[@]}"
