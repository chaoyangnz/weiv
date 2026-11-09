# Weiv compiler

The Weiv CLI is implemented in Cyna. It uses the retained Rust script backend
for JavaScript and TypeScript analysis and the JavaScript runtime packaged by
`weivjs`. The current native package target is macOS arm64.

## Build and verify

From the repository root, with Cyna 0.5.0, Cargo, and the macOS SDK installed:

```sh
npm run build:cyna
cyna check .
cyna test .
cyna fmt src --check
python3 tools/test-cyna-cli.py
python3 tools/test-cyna-project.py
npm run pkg:smoke
```

The build command compiles the Rust backend with locked dependencies, creates
`cyna-out/bin/weiv`, and copies that binary into the macOS arm64 platform
package. Set `CYNA` to select a specific Cyna compiler executable. On macOS,
the build script supplies `SDKROOT` from `xcrun` when it is unset.

## CLI

```sh
cyna-out/bin/weiv emit js test/examples/slots/CardUsage.weiv
cyna-out/bin/weiv emit css test/examples/slots/CardUsage.weiv
cyna-out/bin/weiv emit app test/examples/slots/CardUsage.weiv /tmp/weiv-app
cyna-out/bin/weiv dev test/examples/slots/CardUsage.weiv
```

`emit app` follows local component and module imports, transpiles TypeScript
through the Rust backend, and writes component modules plus `styles.css`.
Pass `--runtime-dir packages/weiv/dist/runtime` before the command to copy the
browser runtime into the output directory. Build that runtime with
`npm run build --prefix packages/weiv` when needed. Without the runtime
directory, generated modules retain virtual runtime imports for a bundler.

`emit js` writes the entry module to standard output. `emit css` writes the
project stylesheet. `emit module-cells` lowers a JavaScript or TypeScript
module for managed shared state. `analyze state-boundaries` reports dependency
warnings. `--json-diagnostics` selects structured CLI diagnostics.

The compiler sources and permanent tests live under `src`.
`docs/compiler/ARCHITECTURE.md` describes the pipeline. The former compiler
and its comparison history are retained on the `legacy` branch.
