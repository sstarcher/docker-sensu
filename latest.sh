#!/bin/sh
set -e
curl -s http://sensu.global.ssl.fastly.net/apt/pool/stretch/main/s/sensu/ | grep - | sed -n 's/.*\(sensu_.*\)_.*/\1/p' | sort | tail -n1