# Weiv — v1 Roadmap

## Recently Closed

- [x] Ship single-package npm surface as `weivjs` with:
  - `weiv` CLI
  - `weivjs/vite` and `weivjs/bun` adapter exports
  - optional `weiv:*` typings (`weiv:observable`, `weiv:router`)
- [x] Publish macOS arm64 platform package (`@weivjs/weiv-darwin-arm64`) and `weivjs`
- [x] Add package-level clean-install E2E verification (`npm run test:package`)
- [x] Split VS Code extension into a standalone repo and wire docs/publish flow around it
- [x] Ship canonical CLI diagnostics mode (`--json-diagnostics`) with contract tests
- [x] Normalize `weiv dev` info logs and harden watch ergonomics (tunable poll/debounce, scan throttling)
- [x] Scaffold UI package split:
  - `@weivjs/ui-core` (headless behavior primitives)
  - `@weivjs/ui-theme-default` (token/theme starter)

## Must-Have (blocking v1)

- [x] Reduce `evaluate(...)` fallbacks — compile dynamic expressions to direct access
- [x] Diagnostics unification — structured author errors across primary CLI/dev failure paths
- [x] App-scale verification — kanib as the primary confidence anchor
- [x] `weiv dev` polish — solid authoring loop, rebuild clarity, process ergonomics

## Should-Have (v1 quality bar)

- [x] Bounded managed state contract and default CLI/Vite/Bun adoption — see [`weiv-arch/docs/component-state-contract.md`](../weiv-arch/docs/component-state-contract.md) and `packages/weiv/README.md`
- [x] Retire legacy reactivity selection and migrate regression consumers to the managed model — see [`reactivity rollout`](../weiv-arch/docs/reactivity-rollout.md)

- [ ] Dependency precision — direct imported observable member paths are selective; extend safe precision to compound expressions and dynamic access
- [x] Observable-to-region mapping — shared state wakes regions depending on the imported binding, not the whole component
- [x] IDE `emit` typing — sibling VS Code extension supplies virtual TypeScript declarations from `export interface Emits`
- [ ] Remove retired `weivUpdate` virtual declarations from the sibling VS Code extension

## Bundler Integration

Goal: `npm install weivjs` with thin bundler adapters. Adapter intercepts `.weiv` imports, calls the compiler, and returns compiled JS.

**Current package architecture:**
```
weivjs                 — CLI + adapter exports
weivjs/bun             — Bun adapter surface
weivjs/vite            — Vite adapter surface
```

**Compiler distribution options (decision pending):**

| Option | How | Pros | Cons |
|--------|-----|------|------|
| WASM | Compile Zig+Rust to `wasm32-wasi`, ship `.wasm` in npm | Single artifact, all platforms, no native deps | Zig+Rust cross-toolchain WASM linking is unproven; ~10% slower |
| Native + NAPI-RS | Prebuilt binaries per platform via `optionalDependencies` | Fastest runtime, proven pattern (SWC, esbuild) | Platform matrix packaging, CI complexity |
| CLI exec | Plugin shells out to `weiv` binary on PATH | Works today, zero new infra | Users install `weiv` separately, process-per-file overhead |

**Industry reference:**
- Svelte, Vue, Angular — compiler is pure JS, direct import. No native code.
- SWC, esbuild, Lightning CSS, Turbopack — native code distributed as platform-specific npm packages via `optionalDependencies`, with optional WASM fallback.

**Weiv compiler stats:** ~9200 lines of Zig (parse → analyze → lower → emit) + ~1700 lines of Rust (Oxc parser backend). Rewriting to JS is not viable.

**Current path:** CLI-exec bridge is implemented inside `weivjs` adapters. Next step is performance/distribution hardening without changing the adapter API.

### Next Actions (Bun + Vite)

- [ ] Improve Bun adapter reliability for larger apps (watch rebuild behavior, diagnostics polish).
- [ ] Improve Vite adapter reliability for larger apps (watch rebuild behavior, diagnostics polish).
- [ ] Add minimal sample apps proving direct `.weiv` import works in Bun and Vite dev mode.
- [ ] Add CI smoke tests for both plugin paths (dev/build or equivalent non-interactive checks).
- [ ] Define migration path from CLI-bridge to native or wasm compiler distribution without changing plugin user API.
- [ ] Replace remaining non-mac platform placeholder binaries and publish full optional-dependency matrix.

See: https://weiv.dev/npm-single-package-distribution

## Post-v1

- SSR / hydration
- Forms package
- Transitions engine
- Public reactivity APIs (signal/ref/proxy)
- Testing helpers
- Async resource primitives

## UI Library Track (`@weivjs/ui-*`)

- [x] Establish split architecture: headless core + themed visual layer
- [x] Publishable package scaffolds for `@weivjs/ui-core` and `@weivjs/ui-theme-default`
- [x] Implement first full primitive contract (Dialog: focus restore, escape, outside click semantics)
- [ ] Add core form-control primitives (Field, Input, Select, Checkbox, Radio)
- [ ] Add default theme variants and density modes
- [x] Add UI package integration examples in Kanib or dedicated sample app

## VS Code Extension DX

- [ ] Diagnostics: run `weiv compile analyze --json` on save, show errors/warnings inline
- [ ] Hover: show type/prop interface on hover for `bind:` values and component tags
- [ ] Autocomplete: suggest script-declared functions/variables inside `bind:` and `on:` attributes
- [ ] Outline: show template structure + script declarations in sidebar symbol view
- [ ] Snippets: common `.weiv` patterns (component scaffold, props, emit)
- [ ] `weiv dev` HMR: hot reload on save instead of full page rebuild
- [ ] Error overlay: show compile errors in the browser during dev
