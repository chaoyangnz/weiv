#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../.."
source scripts/buildkite/runner-path.sh
platform="${1:?platform required}"
case "$platform:$(uname -s):$(uname -m)" in
  macos:Darwin:arm64|linux:Linux:x86_64) ;;
  *) echo "Wrong runner for $platform" >&2; exit 1 ;;
esac
buildkite-agent artifact download 'dist/release/collected/manifest.json' . --step collect-release
version="$(node -p "JSON.parse(require('fs').readFileSync('dist/release/collected/manifest.json')).version")"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
cd "$tmp"
for attempt in 1 2 3; do
  if npm install --no-audit --no-fund --ignore-scripts "weivjs@$version"; then break; fi
  if [ "$attempt" = 3 ]; then exit 1; fi
  sleep 10
done
node node_modules/weivjs/bin/weiv.mjs --help
node --input-type=module -e "await import('weivjs/vite'); await import('weivjs/bun')"
