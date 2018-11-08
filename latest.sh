#!/bin/sh
set -e
curl -s http://sensu.global.ssl.fastly.net/apt/pool/stretch/main/s/sensu/ | grep - | cut -d'>' -f2 | cut -d'_' -f2 | sort | tail -n1
