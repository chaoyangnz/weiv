#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../.."
export PATH="$HOME/.cargo/bin:/opt/homebrew/bin:$HOME/.bun/bin:$HOME/.cyna/current/bin:$PATH"
for node_bin in "$HOME"/.nvm/versions/node/v22*/bin /opt/neucine-release-tools/node*/bin; do
  if [ -x "$node_bin/npm" ]; then
    export PATH="$node_bin:$PATH"
    break
  fi
done
for tool in node npm bun cargo; do
  command -v "$tool" >/dev/null || { echo "Missing $tool on $HOSTNAME" >&2; exit 1; }
done
platform="${1:?expected macos or linux}"
case "$platform:$(uname -s):$(uname -m)" in
  macos:Darwin:arm64|linux:Linux:x86_64) ;;
  *) echo "Wrong runner for $platform" >&2; exit 1 ;;
esac
branch="${BUILDKITE_BRANCH:?Buildkite branch required}"
[[ "$branch" =~ ^release/v([0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.]+)?)$ ]] || {
  echo "Expected release/vX.Y.Z branch" >&2; exit 1;
}
version="${BASH_REMATCH[1]}"
test "$(git rev-parse HEAD)" = "${BUILDKITE_COMMIT:?Buildkite commit required}"
cyna_version="${CYNA_VERSION:-0.5.1}"
case "$platform" in
  macos) cyna_host="aarch64-apple-darwin" ;;
  linux) cyna_host="x86_64-unknown-linux-gnu" ;;
esac
curl --fail --location --retry 3 --silent --show-error https://cyna.dev/install.sh | \
  sh -s -- "$cyna_version" "$cyna_host"
cyna version
npm ci --ignore-scripts --no-audit --no-fund
npm run format:check
npm ci --prefix packages/vscode-extension --ignore-scripts --no-audit --no-fund
npm test --prefix packages/vscode-extension
node tools/release.mjs plan --version="$version" --preflight-only
if [ "$platform" = linux ]; then
  "$HOME/.cyna/current/llvm/bin/clang" --version
  cyna check cyna.release.linux.toml
  npm run build:cyna
fi
node tools/release.mjs plan --version="$version"
node tools/release.mjs verify
buildkite-agent artifact upload 'dist/release/artifacts/*'
buildkite-agent artifact upload 'dist/release/state/*.json'
