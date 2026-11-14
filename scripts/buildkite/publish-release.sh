#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../.."
source scripts/buildkite/runner-path.sh
test "${RELEASE_PUBLISH:-}" = 1
test "$(git rev-parse HEAD)" = "${BUILDKITE_COMMIT:?Buildkite commit required}"
buildkite-agent artifact download 'dist/release/collected/*' . --step collect-release
node scripts/buildkite/publish-release.mjs
