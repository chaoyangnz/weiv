#!/usr/bin/env bash
set -euo pipefail

cat >&2 <<'MESSAGE'
tools/publish-all.sh is retired. It published source directories and tagged after publication.
Use node tools/release.mjs plan, verify, and the local sink rehearsal documented in RELEASING.md.
Public publishing will be wired only after CI verify passes and will consume verified tarballs.
MESSAGE
exit 1
