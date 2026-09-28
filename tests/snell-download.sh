#!/usr/bin/env bash
# Verify that the pinned integration can be fetched. Never execute its contents.
set -e
repo=$(cd "$(dirname "$0")/.." && pwd)
. "$repo/src/snell.sh"
is_core_dir=$(mktemp -d)
trap 'rm -rf "$is_core_dir"' EXIT
for script in snell.sh ip-binding.sh; do
    path=$(snell_bridge_fetch "$script")
    [[ $(snell_bridge_digest "$path") == "$(snell_bridge_hash "$script")" ]]
    bash -n "$path"
done
printf 'PASS: pinned Snell installer and public-IP manager downloads\n'
