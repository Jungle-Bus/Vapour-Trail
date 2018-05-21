#!/usr/bin/env bash

set -e

if [ -z "$bbox" ]; then
    echo "You need to add the bounding box as a parameter"
    echo "   format: minlon,minlat,maxlon,maxlat"
    echo "   example:'7.40701675415039,43.7229786663231,7.4437522888183585,43.7541091221655'"
    exit 1
fi

docker-compose run --rm --entrypoint "t_rex generate --config /config/config.toml --overwrite true --extent=${bbox} --maxzoom 16 --minzoom 12" t-rex
