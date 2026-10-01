#!/bin/sh
# Downloads the two OpenStreetMap extracts the maps are built from.
# Run from the repository root, then `python3 tools/build_maps.py --preview`.

set -e
cd "$(dirname "$0")/osm"
API=https://overpass-api.de/api/interpreter

USM='[out:json][timeout:60];(way["highway"](43.6585,-70.2825,43.6680,-70.2715);way["junction"](43.6585,-70.2825,43.6680,-70.2715);node["highway"](43.6585,-70.2825,43.6680,-70.2715);node["crossing"](43.6585,-70.2825,43.6680,-70.2715);way["building"](43.6600,-70.2800,43.6660,-70.2735););out body;>;out skel qt;'
OLD_PORT='[out:json][timeout:60];(way["highway"](43.6535,-70.2600,43.6635,-70.2440);node["highway"](43.6535,-70.2600,43.6635,-70.2440);node["crossing"](43.6535,-70.2600,43.6635,-70.2440););out body;>;out skel qt;'

curl -sS --fail --max-time 180 --data-urlencode "data=$USM" "$API" -o usm_area.json
curl -sS --fail --max-time 180 --data-urlencode "data=$OLD_PORT" "$API" -o old_port_area.json
echo "Saved usm_area.json and old_port_area.json"
