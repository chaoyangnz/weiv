#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../.."
version="${CYNA_VERSION:-0.5.1}"
test "$(git rev-parse HEAD)" = "${BUILDKITE_COMMIT:?Buildkite commit required}"
for host in "aarch64-apple-darwin" x86_64-unknown-linux-gnu x86_64-pc-windows-gnu; do
  curl --fail --head --location --retry 2 --silent --show-error \
    "https://downloads.cyna.dev/distributions/$version/$host.tar.gz" >/dev/null
  echo "Cyna $version distribution available for $host"
done
