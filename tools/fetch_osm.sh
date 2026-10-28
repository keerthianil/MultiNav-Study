#!/bin/sh
# Downloads the OpenStreetMap extract the intersection maps are built from:
# Portland's Old Port, from Pearl Street to Gorham's Corner.
# Run from the repository root, then `python3 tools/build_maps.py --preview`.

set -e
cd "$(dirname "$0")/osm"
API=https://overpass-api.de/api/interpreter

OLD_PORT='[out:json][timeout:60];(way["highway"](43.6535,-70.2600,43.6635,-70.2440);node["highway"](43.6535,-70.2600,43.6635,-70.2440);node["crossing"](43.6535,-70.2600,43.6635,-70.2440););out body;>;out skel qt;'

curl -sS --fail --max-time 180 --data-urlencode "data=$OLD_PORT" "$API" -o old_port_area.json
echo "Saved old_port_area.json"
