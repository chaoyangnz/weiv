# NPM Single-Package Distribution (Optional Platform Binaries)

This repo now includes a scaffold for shipping `weivjs` as one installable package that
supports both CLI and bundler adapters.

## Package Layout

- `packages/weiv`
  - CLI launcher: `bin/weiv.mjs`
  - Bundler adapters:
    - `weivjs/vite`
    - `weivjs/bun`
  - virtual runtime module typing:
    - `weiv:observable`
    - `weiv:router`
  - Source modules under `src/` (including runtime and binary resolver)
- `packages/weiv-<platform>`
  - `@weivjs/weiv-darwin-arm64`
  - `@weivjs/weiv-darwin-x64`
  - `@weivjs/weiv-linux-x64-gnu`
  - `@weivjs/weiv-linux-arm64-gnu`
  - `@weivjs/weiv-win32-x64-msvc`

## Resolution Order

`packages/weiv/src/platform.mjs` resolves the executable in this order:

1. `WEIV_BINARY_PATH`
2. platform optional dependency package binary
3. fail with actionable guidance

(Download fallback is not wired yet; add later if desired.)

## Release Workflow

1. Build and smoke-test supported platform binaries in CI.
2. Upload the binaries to the matching GitHub release.
3. Publish platform packages first through npm trusted publishing.
4. Publish `weivjs` with `optionalDependencies` pointing to the released native packages.

## Local Validation

From repo root:

```bash
npm run pkg:smoke
```

This validates:

- `weivjs` tarball packs correctly
- bundler adapter exports load (`weivjs/vite`, `weivjs/bun`)
- CLI launcher resolves and executes with `WEIV_BINARY_PATH`

## Important

Release `0.1.1` ships real binaries through
`@weivjs/weiv-darwin-arm64` and `@weivjs/weiv-win32-x64-msvc`. The macOS x64
and Linux package variants remain at `0.1.0` and still need real release
binaries before Weiv has full cross-platform coverage.
