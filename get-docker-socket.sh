#!/usr/bin/env bash
set -e

# get from env if set, otherwise detect
socket="${DOCKER_HOST:-}"

if [ -z "$socket" ]; then
    #  default socket location on Linux/macOS
    if [ -S "/var/run/docker.sock" ]; then
        socket="/var/run/docker.sock"
    # windows named pipe location
    elif [ -p "//./pipe/docker_engine" ] || [ -S "//./pipe/docker_engine" ]; then
        socket="npipe:////./pipe/docker_engine"
    else
        echo "Cannot find Docker socket!" >&2
        exit 1
    fi
fi

# strip prefix to get just the socket path
socket="${socket#unix://}"

echo "$socket"
