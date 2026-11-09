<p align="center">
  <img src="https://weiv.dev/assets/weiv.png" alt="weiv" width="120" />
</p>

Frontend, with room to breathe.

`weiv` is a compiler-first frontend framework for single-file components,
direct DOM updates, and a shared reactive runtime.

- single-file components with clear template, script, and style boundaries
- TypeScript-friendly authoring without JSX
- plain local state by default
- automatic supported shared state inside the managed project boundary
- explicit observable or subscription boundaries for external mutable state
- direct DOM updates instead of a framework-wide VDOM layer
- runtime-level routing integrated with emitted component lifecycle

## Status

Runnable today, still pre-v1.

The current checkpoint includes a working direct-DOM browser path,
managed local/shared reactivity by default, slot composition, external observable
integration, runtime routing, and growing runtime/component verification.

The project is now beyond the initial experimental phase, but still needs:

- more precise dependency analysis
- broader app-scale verification
- diagnostics unification
- IDE/tooling polish
- additional runtime precision work

before it should be treated as production-ready.

## Quick Start

Install the published package:

```bash
npm i -D weivjs
```

Then run the included CLI:

```bash
npx weiv --help
npx weiv dev path/to/App.weiv
```

Supported local state updates automatically, including writes from browser events,
timers, Promises and external callbacks. State writes are immediate; DOM patches
are batched into microtasks. The app builder and Vite/Bun plugins also manage
supported project shared state. See the [state contract and migration guide](packages/weiv/README.md#state-contract-managed-reactivity-by-default).

This describes the current source. Published packages require a matching compiler
and runtime release to provide this default.

If you want a static bundle instead of the dev server:

```bash
npx weiv compile path/to/App.weiv
cd ./dist
bun server.ts
```

`compile` writes to `dist` by default. Pass an explicit output directory when
you want a different bundle location:

```bash
npx weiv compile path/to/App.weiv ./public
```

## NPM Package

`weivjs` is now published with:

- CLI command: `weiv`
- bundler adapters: `weivjs/vite`, `weivjs/bun`
- optional typings: `weiv:observable`, `weiv:router`

See packaging details in the [NPM Single-Package Distribution docs](https://weiv.dev/npm-single-package-distribution).

## Diagnostics JSON

For tooling and machine-readable failure handling:

```bash
npx weiv --json-diagnostics emit js path/to/App.weiv
```

This emits canonical diagnostics JSON with:

- `action`
- `sourcePath`
- `ok`
- `diagnostics` (`code`, `severity`, `stage`, `message`, `location`, `span`, `fatal`)

## Compiler Architecture

The compiler is organized as a sequence of explicit representations:

```text
parser  -> SFC document + template AST
sema    -> ScriptFacts + TemplateBindings
lower   -> LIR
backend -> browser RenderTree + emitted artifacts
```

The parser owns the `.weiv` document shape: a single-file component has a
template section, a script section, and optional style section. Template syntax
is parsed into a template AST. Script and style stay as raw section text at this
layer so the document representation is complete without making parser own
TypeScript semantics.

Semantic analysis turns the raw script into `ScriptFacts` through the Rust FFI
script backend, then binds template references into `TemplateBindings`. The
lowering phase converts the target-neutral component information into LIR.
After that, `ComponentUnit` aggregates the phase outputs for one component.

Browser-specific work lives under the browser backend. It builds a `RenderTree`
from LIR, wraps browser-specific facts in `BrowserComponent`, and emits JavaScript,
scoped CSS, or a whole app bundle. App bundles additionally use an app graph to
collect component and runtime dependencies.

Useful compiler representations can be emitted directly:

```bash
npx weiv emit ast path/to/App.weiv
npx weiv emit sir path/to/App.weiv
npx weiv emit lir path/to/App.weiv
npx weiv emit render-tree path/to/App.weiv
npx weiv emit invalidation-graph path/to/App.weiv
```

Each of those writes to stdout by default. Add an output file to materialize it:

```bash
npx weiv emit lir path/to/App.weiv App.lir.txt
```

## Learn More

Public docs live at [weiv.dev](https://weiv.dev).

- [Docs Index](https://weiv.dev/)
- [Framework Vision](https://weiv.dev/framework-vision)
- [Current Architecture](https://weiv.dev/architecture)
- [Current Status](https://weiv.dev/status)
- [NPM Single-Package Distribution](https://weiv.dev/npm-single-package-distribution)

## Contributor Commands

Build the source checkout CLI and Darwin arm64 package binary with Cyna 0.5.0
and Cargo. The Zig commands exercise the preserved reference compiler; they
require Zig 0.16 because Zig 0.17 is not compatible with `build.zig`.

```bash
npm run build:cyna
cyna check cyna-port
cyna test cyna-port
npm run pkg:smoke
zig build test
zig build component-test
zig build runtime-test
zig build test-all
npm run test:package
```
