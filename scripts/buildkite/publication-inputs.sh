#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../.."
tag="${BUILDKITE_TAG:?Release tag required}"
[[ "$tag" =~ ^v[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.]+)?$ ]] || exit 1
test "$(git rev-parse HEAD)" = "${BUILDKITE_COMMIT:?Buildkite commit required}"
test "$(git rev-list -n 1 "$tag")" = "$BUILDKITE_COMMIT"
echo "Public publication is not implemented in tools/release.mjs. Candidate tarballs must be collected and verified across hosts before this step can publish." >&2
exit 1
