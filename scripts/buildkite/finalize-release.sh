#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../.."
source scripts/buildkite/runner-path.sh
buildkite-agent artifact download 'dist/release/collected/*' . --step collect-release
tag="$(node -p "JSON.parse(require('fs').readFileSync('dist/release/collected/manifest.json')).tag")"
commit="$(node -p "JSON.parse(require('fs').readFileSync('dist/release/collected/manifest.json')).commit")"
test "$commit" = "${BUILDKITE_COMMIT:?Buildkite commit required}"
test "$(git ls-remote origin "refs/tags/$tag^{}" | cut -f1)" = "$commit"
if ! gh release view "$tag" >/dev/null 2>&1; then
  gh release create "$tag" dist/release/collected/*.tgz dist/release/collected/SHA256SUMS \
    --verify-tag --title "Weiv $tag" --notes "Verified by Buildkite build ${BUILDKITE_BUILD_URL:?}."
fi
gh release view "$tag" --json tagName,url
