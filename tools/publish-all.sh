#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

DRY_RUN=0
TAG_RELEASE=0
VERSION_OVERRIDE=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run)
      DRY_RUN=1
      shift
      ;;
    --tag)
      TAG_RELEASE=1
      shift
      ;;
    --version)
      VERSION_OVERRIDE="${2:-}"
      shift 2
      ;;
    -h|--help)
      cat <<'EOF'
Usage: tools/publish-all.sh [--dry-run] [--tag] [--version <x.y.z>]

Options:
  --dry-run         Run npm publish in dry-run mode.
  --tag             Create and push git tag v<version> after successful publish.
  --version <x.y.z> Override version used for tag step (defaults to packages/weiv/package.json).
EOF
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      exit 1
      ;;
  esac
done

if [[ "$DRY_RUN" -eq 0 ]]; then
  if [[ -n "$(git status --porcelain)" ]]; then
    echo "Working tree is not clean. Commit/stash changes before publish." >&2
    exit 1
  fi
fi

echo "==> Running release checks"
npm run pkg:release-check

PUBLISH_FLAGS=(--access public)
if [[ "$DRY_RUN" -eq 1 ]]; then
  PUBLISH_FLAGS+=(--dry-run)
fi

publish_pkg() {
  local pkg_dir="$1"
  echo "==> Publishing ${pkg_dir} ${PUBLISH_FLAGS[*]}"
  npm publish "$pkg_dir" "${PUBLISH_FLAGS[@]}"
}

# Platform packages first
a=(
  "./packages/weiv-darwin-arm64"
)

for pkg in "${a[@]}"; do
  publish_pkg "$pkg"
done

# Main package last
publish_pkg "./packages/weiv"

if [[ "$TAG_RELEASE" -eq 1 && "$DRY_RUN" -eq 0 ]]; then
  VERSION="$VERSION_OVERRIDE"
  if [[ -z "$VERSION" ]]; then
    VERSION="$(node -p "require('./packages/weiv/package.json').version")"
  fi
  TAG="v${VERSION}"
  echo "==> Tagging release ${TAG}"
  git tag "$TAG"
  git push origin "$TAG"
fi

echo "Publish flow complete."
