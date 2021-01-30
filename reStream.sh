#!/bin/sh

# default values for arguments
remarkable="10.11.99.1"   # remarkable connected through USB
landscape=true            # rotate 90 degrees to the right
output_path=-             # display output through ffplay
format=-                  # automatic output format
webcam=false              # not to a webcam
measure_throughput=false  # measure how fast data is being transferred
window_title=reStream     # stream window title is reStream
video_filters=""          # list of ffmpeg filters to apply
unsecure_connection=false # Establish a unsecure connection that is faster

# loop through arguments and process them
while [ $# -gt 0 ]; do
    case "$1" in
        -p | --portrait)
            landscape=false
            shift
            ;;
        -s | --source)
            remarkable="$2"
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
        -m | --measure)
            measure_throughput=true
            shift
            ;;
        -w | --webcam)
            webcam=true
            format="v4l2"

            # check if there is a modprobed v4l2 loopback device
            # use the first cam as default if there is no output_path already
            cam_path=$(v4l2-ctl --list-devices \
                | sed -n '/^[^\s]\+platform:v4l2loopback/{n;s/\s*//g;p;q}')

            # fail if there is no such device
            if [ -e "$cam_path" ]; then
                if [ "$output_path" = "-" ]; then
                    output_path="$cam_path"
                fi
            else
                echo "Could not find a video loopback device, did you"
                echo "sudo modprobe v4l2loopback"
                exit 1
            fi
            shift
            ;;
        -t | --title)
            window_title="$2"
            shift
            shift
            ;;
        -u | --unsecure-connection)
            unsecure_connection=true
            shift
            ;;
        -h | --help | *)
            echo "Usage: $0 [-p] [-u] [-s <source>] [-o <output>] [-f <format>] [-t <title>]"
            echo "Examples:"
            echo "	$0                              # live view in landscape"
            echo "	$0 -p                           # live view in portrait"
            echo "	$0 -s 192.168.0.10              # connect to different IP"
            echo "	$0 -o remarkable.mp4            # record to a file"
            echo "	$0 -o udp://dest:1234 -f mpegts # record to a stream"
            echo "  $0 -w                           # write to a webcam (yuv420p + resize)"
            echo "  $0 -u                           # establish a unsecure but faster connection"
            exit 1
            ;;
    esac
done

ssh_cmd() {
    echo "[SSH]" "$@" >&2
    ssh -o ConnectTimeout=1 -o PasswordAuthentication=no "root@$remarkable" "$@"
}

# check if we are able to reach the remarkable
if ! ssh_cmd true; then
    echo "$remarkable unreachable or you have not set up an ssh key."
    echo "If you see a 'Permission denied' error, please visit"
    echo "https://github.com/rien/reStream/#installation for instructions."
    exit 1
fi

rm_version="$(ssh_cmd cat /sys/devices/soc0/machine)"

case "$rm_version" in
    "reMarkable 1.0")
        width=1408
        height=1872
        bytes_per_pixel=2
        fb_file="/dev/fb0"
        pixel_format="rgb565le"
        ;;
    "reMarkable 2.0")
        if ssh_cmd "[ -f /dev/shm/swtfb.01 ]"; then
            width=1404
            height=1872
            bytes_per_pixel=2
            fb_file="/dev/shm/swtfb.01"
            pixel_format="rgb565le"
        else
            width=1872
            height=1404
            bytes_per_pixel=1
            fb_file=":mem:"
            pixel_format="gray8"
            video_filters="$video_filters,transpose=2"
        fi
        ;;
    *)
        echo "Unsupported reMarkable version: $rm_version."
        echo "Please visit https://github.com/rien/reStream/ for updates."
        exit 1
        ;;
esac

# technical parameters
loglevel="info"
decompress="lz4 -d"

# check if lz4 is present on the host
if ! lz4 -V >/dev/null; then
    echo "Your host does not have lz4."
    echo "Please install it using the instruction in the README:"
    echo "https://github.com/rien/reStream/#installation"
    exit 1
fi

# check if restream binay is present on remarkable
if ssh_cmd "[ ! -f ~/restream ] && [ ! -f /opt/bin/restream ]"; then
    echo "The restream binary is not installed on your reMarkable."
    echo "Please install it using the instruction in the README:"
    echo "https://github.com/rien/reStream/#installation"
    exit 1
fi

# use pv to measure throughput if desired, else we just pipe through cat
if $measure_throughput; then
    if ! pv --version >/dev/null; then
        echo "You need to install pv to measure data throughput."
        exit 1
    else
        loglevel="error" # verbose ffmpeg output interferes with pv
        host_passthrough="pv"
    fi
else
    host_passthrough="cat"
fi

# store extra ffmpeg arguments in $@
set --

# rotate 90 degrees if landscape=true
$landscape && video_filters="$video_filters,transpose=1"

# Scale and add padding if we are targeting a webcam because a lot of services
# expect a size of exactly 1280x720 (tested in Firefox, MS Teams, and Skype for
# for business). Send a PR if you can get a higher resolution working.
if $webcam; then
    video_filters="$video_filters,format=pix_fmts=yuv420p"
    video_filters="$video_filters,scale=-1:720"
    video_filters="$video_filters,pad=1280:0:-1:0:#eeeeee"
fi

# set each frame presentation time to the time it is received
video_filters="$video_filters,setpts=(RTCTIME - RTCSTART) / (TB * 1000000)"

set -- "$@" -vf "${video_filters#,}"

if [ "$output_path" = - ]; then
    output_cmd=ffplay

    window_title_option="-window_title $window_title"
else
    output_cmd=ffmpeg

    if [ "$format" != - ]; then
        set -- "$@" -f "$format"
    fi

    set -- "$@" "$output_path"
fi

set -e # stop if an error occurs

restream_options="-h $height -w $width -b $bytes_per_pixel -f $fb_file"

# shellcheck disable=SC2089
restream_rs="PATH=\"\$PATH:/opt/bin/:.\" restream $restream_options"
if $unsecure_connection; then
    listen_port=16789
    ssh_cmd "$restream_rs --listen $listen_port" &
    sleep 1 # give some time to restream.rs to start listening
    receive_cmd="nc $remarkable $listen_port"
else
    receive_cmd="ssh_cmd $restream_rs"
fi

# shellcheck disable=SC2086,SC2090
$receive_cmd \
    | $decompress \
    | $host_passthrough \
    | ("$output_cmd" \
        -vcodec rawvideo \
        -loglevel "$loglevel" \
        -f rawvideo \
        -pixel_format "$pixel_format" \
        -video_size "$width,$height" \
        $window_title_option \
        -i - \
        "$@" \
        ; kill $$
    )
