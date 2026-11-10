# Weiv releasing

The canonical release contract is in daydream `shared/decisions/0001-canonical-release-process.md`.
The version entry points are `packages/weiv/package.json`, the platform package manifest, and the main package's optional dependency. The macOS ARM64 binary under `packages/weiv-darwin-arm64/bin` is committed release input; verification checks its format and packs that exact binary. The VS Code extension has a separate repository and release flow.

Run `node tools/release.mjs plan --preflight-only` before expensive gates. For an offline rehearsal on a release candidate commit, run `node tools/release.mjs rehearse`; local experimentation on a dirty tree or existing version may use `--allow-dirty`. The rehearsal runs the component/runtime suite against the committed binary, checks the Vite plugin, packs npm tarballs, installs the main tarball in a local consumer, copies the verified tarballs into the local sink, checks their hashes, and renders `state/record.md`. It creates no tag or remote publication. The local component/runtime suite passed 170 tests and the Cyna suite passed 407 tests on 2026-11-10.

CI's manual `release-verify.yml` accepts version, platform, and `preflight` or `verify`. It uploads packed tarballs and hashes for review. Public tagging and publishing are not wired. The former `publish-supported-release.yml` workflow was removed and `tools/publish-all.sh` is retired because they published before canonical verification.

Before public publication is wired, the verified artifacts must be consumed unchanged, with an annotated tag on the verified commit after all gates and registry packages published in dependency order. A release record belongs in `daydream/projects/weiv/docs/releases/` after publication.
