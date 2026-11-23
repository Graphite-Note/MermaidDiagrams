#!/bin/sh
# File: bundle.sh
# ---------------
# Layer: Tooling
# Description: Runs pele-bundler.ts in Deno's sandbox, which joins Pele's modules into one plain script for
#              JavaScriptCore (pele-bundle.js) and records what it draws of each documentation example
#              (pele-bundle-drawings.json): read access to Pele's tree, this folder and the output's Deno cache only,
#              write access to the output folder only, no network, no subprocess, no environment.
#
# Authors: Bahey Shalash
# Version: 0.1
# Date: 23/11/2026
#
# Usage: scripts/pele/bundle.sh <pele checkout> <output folder>
set -eu
pele=$(cd "$1" && pwd)
output=$2
runner=$(cd "$(dirname "$0")" && pwd)
mkdir -p "$output"
output=$(cd "$output" && pwd)
version=$(sed -n 's/^  "version": "\(.*\)",$/\1/p' "$pele/package.json")
# As run.sh: Pele's package.json is answered by a module holding its version, for the info diagram.
map="data:application/json,{\"imports\":{\"file://$pele/package.json\":\"data:application/typescript,export const version = '$version';\"}}"
# A cache of the output's own, made anew, holds only what Deno transpiles of Pele for this run.
cache="$output/deno-cache"
rm -rf "$cache"
DENO_DIR="$cache" TZ=UTC exec deno run --unstable-sloppy-imports --no-prompt --import-map="$map" \
  --allow-read="$pele,$runner,$cache" --allow-write="$output" \
  "$runner/pele-bundler.ts" "$pele" "$cache" "$output"
