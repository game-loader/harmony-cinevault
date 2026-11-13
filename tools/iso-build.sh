#!/usr/bin/env bash
# Compile-check the current tree in a private copy so parallel agents don't clash on entry/build.
#   tools/iso-build.sh <name>     -> builds in /tmp/cv-iso-<name>
set -uo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
name="${1:?name}"
dst="/tmp/cv-iso-$name"
mkdir -p "$dst"
rsync -a --delete --exclude node_modules --exclude 'entry/build' --exclude .hvigor --exclude .git "$root/" "$dst/"
ln -sfn "$root/node_modules" "$dst/node_modules"
cd "$dst" && bash tools/build.sh debug
