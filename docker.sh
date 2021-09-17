#!/bin/bash
set -e

if [[ "$OSTYPE" == "linux-gnu"* ]]; then
  xhost local:root
elif [[ "$OSTYPE" == "darwin"* ]]; then
  DISPLAY="host.docker.internal:0"
  xhost +localhost
elif [[ "$OSTYPE" =~ ^cygwin|msys$ ]]; then
  DISPLAY="$(route.exe print | grep 0.0.0.0 | head -1 | awk '{print $4}'):0.0"
fi

docker build -t restream .
docker run \
  --env DISPLAY=$DISPLAY \
  --env SSH_AUTH_SOCK=/ssh-agent \
  --network host \
  --volume /tmp/.X11-unix:/tmp/.X11-unix \
  --volume $SSH_AUTH_SOCK:/ssh-agent \
  -it \
  restream "$@"
