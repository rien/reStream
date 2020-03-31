#!/bin/sh

# these are probably the only parameters you need to change
ssh_host_usb="root@10.11.99.1" # location of the remarkable using usb
ssh_host_wifi=""               # location of the remarkable using wifi
landscape=true             # default vertical
if [ "$1" = "-p" ]         # call with -p if you want vertical
then
    landscape=false
fi

# technical parameters
width=1408
height=1872
bytes_per_pixel=2
loop_wait="true"
loglevel="info"

# check if we are able to reach the remarkable
if ! ssh -o ConnectTimeout=1 "$ssh_host_usb" true; then
  if ! [ -z "$ssh_host_wifi" ]; then
    if ! ssh "$ssh_host_wifi" true; then
      echo "$ssh_host_wifi unreachable"
      exit 1
    else
      ssh_host=$ssh_host_wifi
      echo "usb host not reachable, using wifi instead"
    fi
  else
    echo "usb host not reachable, wifi host not specified"
    exit 1
  fi
else
  ssh_host=$ssh_host_usb
fi


fallback_to_gzip() {
    echo "Falling back to gzip, your experience may not be optimal."
    echo "Go to https://github.com/rien/reStream/#sub-second-latency for a better experience."
    compress="gzip"
    decompress="gzip -d"
    sleep 2
}


# check if lz4 is present on remarkable
if ssh "$ssh_host" "[ -f /opt/bin/lz4 ]"; then
    compress="/opt/bin/lz4"
elif ssh "$ssh_host" "[ -f ~/lz4 ]"; then
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




# calculte how much bytes the window is
window_bytes="$(($width*$height*$bytes_per_pixel))"

# rotate 90 degrees if landscape=true
landscape_param="$($landscape && echo '-vf transpose=1')"

# read the first $window_bytes of the framebuffer
head_fb0="dd if=/dev/fb0 count=1 bs=$window_bytes 2>/dev/null"

# loop that keeps on reading and compressing, to be executed remotely
read_loop="while $head_fb0; do $loop_wait; done | $compress"

set -e # stop if an error occurs

ssh  "$ssh_host" "$read_loop" \
    | $decompress \
    | ffplay -vcodec rawvideo \
             -loglevel "$loglevel" \
             -f rawvideo \
             -pixel_format gray16le \
             -video_size "$width,$height" \
             $landscape_param \
             -i -
