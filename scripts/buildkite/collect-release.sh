#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../.."
source scripts/buildkite/runner-path.sh
platforms=("$@")
test "${#platforms[@]}" -eq 3
for platform in "${platforms[@]}"; do
  destination="dist/release/candidates/$platform"
  mkdir -p "$destination"
  buildkite-agent artifact download 'dist/release/artifacts/*' "$destination" --step "candidate-$platform"
  buildkite-agent artifact download 'dist/release/state/plan.json' "$destination" --step "candidate-$platform"
  buildkite-agent artifact download 'dist/release/state/verify.json' "$destination" --step "candidate-$platform"
done
node scripts/buildkite/collect-release.mjs "${platforms[@]}"
buildkite-agent artifact upload 'dist/release/collected/*'
