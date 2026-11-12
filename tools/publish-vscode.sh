#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
EXT_DIR="$ROOT_DIR/packages/vscode-extension"

DRY_RUN=0
DO_PUBLISH=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run)
      DRY_RUN=1
      shift
      ;;
    --publish)
      DO_PUBLISH=1
      shift
      ;;
    -h|--help)
      cat <<'EOF'
Usage: tools/publish-vscode.sh [--dry-run] [--publish]

Options:
  --dry-run   Build and package VSIX only.
  --publish   Publish extension to Visual Studio Marketplace.

Notes:
  - Publish requires VSCE_PAT in environment.
  - If both flags are omitted, defaults to --dry-run behavior.
EOF
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      exit 1
      ;;
  esac
done

cd "$EXT_DIR"

echo "==> Installing extension dependencies"
if [[ -d node_modules ]]; then
  echo "node_modules already present; skipping install"
else
  npm ci --ignore-scripts --no-audit --no-fund
fi

echo "==> Building extension"
if ! command -v npx >/dev/null 2>&1; then
  echo "npx is required to build/package the VS Code extension." >&2
  exit 1
fi
npx --no-install tsc -v >/dev/null 2>&1 || {
  echo "TypeScript toolchain not installed for extension workspace." >&2
  echo "Run: cd \"$EXT_DIR\" && npm install" >&2
  exit 1
}
npm run build

echo "==> Packaging VSIX"
npx @vscode/vsce package

if [[ "$DO_PUBLISH" -eq 1 ]]; then
  if [[ -z "${VSCE_PAT:-}" ]]; then
    echo "VSCE_PAT is required for publish." >&2
    exit 1
  fi
  echo "==> Publishing extension"
  npx @vscode/vsce publish -p "$VSCE_PAT"
else
  if [[ "$DRY_RUN" -eq 0 ]]; then
    echo "No mode specified; defaulting to dry-run package only."
  fi
fi

echo "VS Code extension flow complete."
