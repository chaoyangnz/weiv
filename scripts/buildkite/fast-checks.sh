#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../.."
test "$(uname -s)" = Darwin
npm ci --ignore-scripts --no-audit --no-fund
npm run format:check
bun test test/runtime test/ui-core
npm ci --prefix packages/vscode-extension --ignore-scripts --no-audit --no-fund
npm test --prefix packages/vscode-extension
