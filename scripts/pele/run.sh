#!/bin/sh
# File: run.sh
# ------------
# Layer: Tooling
# Description: Runs pele-runner.ts in Deno's sandbox: read access to Pele's tree and this folder only, write access to
#              the output folder only, no network, no subprocess, no environment.
#
# Authors: Bahey Shalash
# Version: 0.2
# Date: 23/11/2026
#
# Usage: scripts/pele/run.sh <pele checkout> <output folder> [--corpus] [--compat] [--random-flat] [--bench] [--svg=<corpus>#<index>,…]
set -eu
pele=$(cd "$1" && pwd)
output=$2
shift 2
runner=$(cd "$(dirname "$0")" && pwd)
mkdir -p "$output"
output=$(cd "$output" && pwd)
version=$(sed -n 's/^  "version": "\(.*\)",$/\1/p' "$pele/package.json")
# The info diagram imports Pele's package.json without an import attribute, which Deno refuses; this import map
# answers that one import with a module holding the same version. Two of Mermaid's specs import vitest, which is
# answered by a stand-in beside the runner.
map="data:application/json,{\"imports\":{\"file://$pele/package.json\":\"data:application/typescript,export const version = '$version';\",\"vitest\":\"file://$runner/vitest-stand-in.ts\"}}"
TZ=UTC exec deno run --unstable-sloppy-imports --no-prompt --import-map="$map" \
  --allow-read="$pele,$runner" --allow-write="$output" \
  "$runner/pele-runner.ts" "$pele" "$output" "$@"
