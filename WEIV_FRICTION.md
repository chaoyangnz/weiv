# Weiv integration friction

## Managed-project reactivity warnings in Neiv Lightcept (2026-11-09)

- **Classification:** needs investigation; compiler diagnostics are non-fatal and the managed project emits successfully.
- **Context:** Lightcept `src/ui/neiv`, Weiv checkout `v0.1.2-11-ged71d0e`, macOS arm64, Node 22.22.1. The app uses `weivUpdate` for callback and subscription state changes.
- **Reproduction:** from `lightcept`, run `node ../weiv/packages/weiv/bin/weiv.mjs compile emit app src/ui/neiv/web/App.weiv /tmp/neiv-web`.
- **Expected:** compilation reports the success result without unresolved reactivity warnings for state explicitly updated through `weivUpdate`.
- **Actual:** compilation succeeds but returns 22 `reactivity.unverified_dependency` warnings. Representative dependencies are `percent` through `PhotoZoomControls` event props, `shadowsPercent` through a reassigned callback, and `hslBands` through a helper return value.
- **Workaround/status:** the app compiles and Neiv check passes. Review whether the managed-state analyzer should understand these adapter patterns before treating the warnings as app defects.

## Cyna cutover component regressions (2026-11-09)

- **Classification:** confirmed Cyna compiler compatibility gaps in mounted component behavior; the package and native Cyna suites pass, while the broader component suite does not.
- **Context:** macOS arm64, Cyna 0.5.0, Bun 1.2.16, Node 22.22.1; `main` uses `cyna-out/bin/weiv` for `test/component/support.ts` and direct component emit tests.
- **Reproduction:** run `npm run build:cyna`, then `npm run test:component` from the repository root.
- **Expected:** all mounted component behaviors pass with the Cyna compiler, including native objects, callable state, alias replacement, and Kanib navigation.
- **Actual:** 55 passed, 11 failed, and 3 unhandled errors across 66 tests. The complete output is reproducible with the command above. Representative failures: `destructuring declarations initialize each binding before subsequent extraction` throws `TypeError: Weiv observable state requires writable data properties`; `inline events preserve loop aliases, script shadows and callback parameters` exits with `Cannot emit JavaScript`; `replacing local aliases releases old graphs and keeps scalar snapshots ordinary` expects update count 2 but receives 3; `replaced callable state subscribes to newly captured roots` expects `"1"` but receives `"0"`; several callback, conversion, and Kanib tests throw `TypeError: Weiv observable state supports only plain objects and arrays`.
- **Workaround/status:** the previous compiler and its passing behavior remain on `legacy`. Keep these tests as active Cyna regression coverage; no test expectations were weakened during the branch cleanup.

## Valid app fails JavaScript emission with no diagnostic (2026-11-10)

- **Classification:** confirmed CLI/tooling defect or missing diagnostic; the same app source previously compiled, and the current validator accepts it.
- **Task/context:** regenerate the Affon performance report (`test/benchmark/report/App.weiv`, about 33 KB) from the retained aggregate JSON. The report uses nested `#for` sections, event handlers, and the `globalThis.__WEIV_PROPS__` payload already consumed by the previous build.
- **Versions/environment:** Weiv `ed71d0e` on `main`, macOS arm64, Node 22.x, CLI invoked as `/Users/chao.yang/Private/weiv/node_modules/.bin/weiv`. The app source and the previously generated HTML bundle are unchanged since the successful 2026-11-07 build.
- **Reproduction:** from the Affon repository run `weiv compile test/benchmark/report/App.weiv /tmp/affon-weiv-report`. Also run `weiv emit js test/benchmark/report/App.weiv /tmp/app.js` and `weiv --json-diagnostics emit js test/benchmark/report/App.weiv /tmp/app.js`.
- **Expected:** compilation emits the browser project, or the validator/emitter reports at least one fatal diagnostic with a source location.
- **Actual:** `weiv validate app test/benchmark/report/App.weiv --json` returns `"ok": true` with only non-fatal `helper.external_state` and `helper.side_effects` warnings. `weiv compile` exits 1 with only `Cannot build browser project: browser emission failed`. `weiv emit js` exits 2 with only `Cannot emit JavaScript`. `--json-diagnostics` adds no diagnostic detail. The HEAD version of the same app fails identically.
- **Further diagnosis (2026-11-10):** at commit `1a33328`, a temporary diagnostic build that printed the caught `JavaScriptError` variant identified `unsupported_template` from `emit_browser_module`. The temporary source instrumentation was removed after diagnosis. `emit sir`, `emit lir`, and `emit css` succeed on the same file; `emit js` fails. The source has nested `#for` loops, which `src/compiler/backend/browser/emit/js_module/emit_loops.cy` rejects in `validate_body`, though the precise failing node has not yet been isolated. Expected: either support the validated template or report the unsupported node and location. Environment: macOS arm64, Node 22.22.1, Cyna 0.5.0, `weivjs` 0.1.2. Reproduce with `node_modules/.bin/weiv emit js ../affon/test/benchmark/report/App.weiv /tmp/affon-report.js` from the Weiv checkout; actual output is `Cannot emit JavaScript` and exit 2.
- **Workaround/verification:** regenerate the report data with the Python generator, then replace the `globalThis.__WEIV_PROPS__={...}` payload in the last successfully compiled HTML bundle while preserving its emitted script and CSS. The resulting HTML loads with the new 23,900 operator and 23,895 Program cases. Automatic recompilation remains blocked until the emitter returns a diagnostic.

## Cyna emit js duplicates JSON diagnostics on fatal cell error (2026-11-09)

- **Classification:** confirmed Cyna port CLI output defect; fixed in the current source and rebuilt Darwin arm64 binary.
- **Context:** Darwin arm64, Cyna 0.5.0, Node 22.22.1, Weiv Cyna port and retained Rust script backend.
- **Reproduction:** build with `npm run build:cyna`, then run `node test/package/cell-diagnostics.test.mjs`. The first fixture is `<p>{{ count++ }}</p>` with `let count=0;`, compiled through `weiv --json-diagnostics emit js`.
- **Expected:** one JSON failure report with `reactivity.render_mutation`, parseable as a single document.
- **Actual:** stderr contained a warning JSON report followed by the fatal JSON report. `JSON.parse` failed with `SyntaxError: Unexpected non-whitespace character after JSON at position 774 (line 4 column 1)`; the test exited 1.
- **Cause and fix:** the direct `emit js` path printed state boundary warnings before checking fatal cell diagnostics. It now checks cell diagnostics first and returns on a fatal error, leaving one JSON report. The normal warning path remains available after successful validation. Rebuilt with `npm run build:cyna`; `node test/package/cell-diagnostics.test.mjs` and the full `test/package/*.test.mjs` suite pass.

## Affon report compile allocator mismatch (2026-11-07)

- **Classification:** confirmed compiler tooling defect in the local Zig 0.16.0 build at commit `c8e7443` with uncommitted source changes; subsequent local binary retest passes. The saved HTML filter test also needed to await Weiv's asynchronous DOM update and is a test timing issue, not a runtime defect.
- **Context:** Affon `test/benchmark/report/App.weiv`, macOS arm64, `weivjs` 0.1.2 source checkout, Zig 0.16.0. The report renderer calls `node_modules/.bin/weiv compile <App.weiv> <temporary output>`.
- **Reproduction:** from `/Users/chao.yang/Private/affon`, run `python3 tools/render-performance-report.py` with the local Weiv binary that existed before the 2026-11-07 rebuild.
- **Expected:** Weiv compiles the report and returns its generated files.
- **Actual:** compilation aborted with `error(DebugAllocator): Allocation size 66 bytes does not match free size 65`. Allocation stack: `std.mem.Allocator.dupeSentinel` → `std.Io.Dir.realPathFileAlloc` → `src/compiler/backend/browser/emit/app/runtime_imports.zig:12 runtimeSource`; free stack: `src/compiler/backend/browser/emit/app/graph.zig:362 copyWeivRuntimeModule` → `allocator.free(runtime_abs_source)`. The command exited from `SIGABRT`, and the report renderer raised `subprocess.CalledProcessError`.
- **Cause and workaround:** Zig 0.16 `realPathFileAlloc` returns a sentinel slice. Returning it as `[]u8` erased the sentinel length for `allocator.free`. The local source now returns `[:0]u8` from `runtimeSource`; rebuilding the Weiv binary and rerunning the Affon report succeeded. No external issue was filed.

## Quick defect index

Status reflects the latest verification recorded here, not the original report. “Fixed in source” means the local checkout has a tested change; publication is unverified unless a released version is named. Related reports share a row. Project-only setup issues and documentation-only findings are omitted.

Status key: 🔴 open · 🟠 needs investigation or retest · 🟡 fixed in source, app retest pending · 🟢 fixed in source · ✅ fixed in a release.

| Defect | Reported | Status | Current status | Details |
| --- | --- | :---: | --- | --- |
| Managed-project reactivity warnings | 2026-11-09 | 🟠 | Needs investigation: 22 warnings, successful emit | [Report](#managed-project-reactivity-warnings-in-neiv-lightcept-2026-11-09) |
| SVG elements use HTML namespace | 2026-11-07 | 🟠 | Current source passes; Lightcept build path needs investigation | [Report](#svg-elements-compile-into-the-html-namespace-2026-11-07) |
| State updates after detached async work | 2026-11-06 | 🔴 | Open: scalar async notifications | [Report](#predictable-state-contract-audit-2026-11-06) |
| Template literal in child prop | 2026-11-06 | 🟡 | Fixed in source; app retest pending | [Report](#custom-component-prop-template-expression-in-ceiv-2026-11-06) |
| Boolean ARIA attribute values | 2026-11-05 | 🟡 | Fixed in source; native retest pending | [Report](#boolean-aria-selected-binding-reports-the-active-tab-as-off-2026-11-05) |
| Scoped element selectors in WKWebView | 2026-11-01 | 🟠 | Unisolated native rendering | [Report](#bare-element-selectors-in-packaged-ceiv-lightcept-ui-2026-11-01) |
| Source adapter selects published binary | 2026-10-31 | 🟢 | Fixed in source | [Report](#source-linked-vite-adapter-can-select-an-older-compiler-binary) |
| Managed imports retain replaced initial objects | 2026-11-07 | 🟢 | Fixed in experimental source; mounted app and bundled regressions pass | [Report](#assignment-patterns-and-managed-import-replacement-2026-11-07) |
| Scalar __proto__ bindings render the scope prototype | 2026-11-07 | 🟢 | Fixed in source with a null-prototype render scope | [Report](#sequential-destructuring-declarations-2026-11-07) |
| Root-relative assets under file URL | 2026-10-29 | 🔴 | Open: packaging support | [Report](#bundling-a-weiv-page-in-a-macos-wkwebview-2026-10-29) |
| Tracked array map/filter | 2026-10-28 | 🟢 | Fixed in source | [Report](#proxied-arrays-break-native-arraymap-in-012-2026-10-28) |
| Template Math/String globals | 2026-10-28 | 🟢 | Fixed in source | [Report](#global-math-unavailable-in-template-expressions-2026-10-28) |
| Inline SVG namespace | 2026-10-28 | 🟢 | Fixed in source | [Report](#svg-template-nodes-use-the-html-namespace-2026-10-28) |
| Malformed script succeeds silently | 2026-10-28 | 🟢 | Fixed in source | [Report](#diagnostics-gap-malformed-typescript-silently-discards-the-component-script) |
| Type-only imports at runtime | 2026-10-28 | 🟢 | Fixed in source | [Report](#published-012-emits-type-only-import-as-runtime-binding-2026-10-28) |
| Vite sibling component imports | 2026-10-28 | 🟢 | Fixed in source | [Report](#published-vite-adapter-does-not-resolve-generated-sibling-component-imports-2026-10-28) |
| Missing platform binary packages | 2026-10-28 | 🔴 | Open: release distribution | [Report](#published-012-lists-unavailable-optional-platform-packages-2026-10-28) |
| Template-bound const | 2026-10-28 | ✅ | Fixed in released 0.1.2 | [Report](#template-bound-const-fails-at-mount-in-published-011-2026-10-28) |
| Object shorthand in child prop | 2026-10-27 | 🟠 | Needs current-source retest | [Report](#compiler-defect-object-shorthand-in-component-props-emits-invalid-javascript) |
| Complex prop expression scope | 2026-10-27 | 🟠 | Needs current-source retest | [Report](#compiler-defect-complex-prop-member-expression-can-remain-unscoped) |
| HTML void tags | 2026-10-27 | 🟢 | Fixed in source | [Report](#diagnostics-gap-html-void-tags-reported-as-mismatched-close-at-template-start) |
| HTML entities in static text | 2026-10-27 | 🟢 | Fixed in source | [Report](#template-compatibility-gap-html-entity-is-shown-literally) |
| Tracked local const reassignment | 2026-10-27 | 🟢 | Fixed in source | [Report](#compiler-defect-local-const-is-reassigned-during-setup) |
| Imported function initialization | 2026-10-27 | 🟢 | Fixed in source | [Report](#top-level-call-to-an-imported-function-runs-before-initialization) |
| Vite component styles | 2026-10-27 | 🟢 | Fixed in source | [Report](#published-vite-plugin-omits-component-styles) |
| Command options in accessibility tree | 2026-10-27 | 🔴 | Open: native cause unisolated | [Report](#native-wkwebview-accessibility-exposes-only-the-first-command-option-2026-10-27) |
| Compound expression scope | 2026-10-27 | 🟢 | Fixed in source; regression passes | [Report](#compound-expressions-lose-component-or-loop-scope) |
| CSP evaluation of component props | 2026-10-27 | 🟢 | Fixed in source | [Report](#packaged-app-csp-incompatibility-component-prop-objects-use-runtime-evaluation) |
| Conditional child updates before mount | 2026-10-27; recurred 2026-11-06 | 🟡 | Guard in source; app retest pending | [Original](#compiler-defect-child-component-in-a-conditional-branch-can-update-before-mount), [Ceiv](#nested-conditional-component-update-in-ceiv-2026-11-06) |
| Loop event helper scope | 2026-10-14 | 🟢 | Fixed in source | [Report](#15-loop-event-expressions-cannot-resolve-outer-component-functions) |
| Async list item update | 2026-10-14 | 🟢 | Fixed for declared async helpers | [Report](#16-async-list-item-updates-do-not-refresh-repeated-bindings) |
| Late conditional mount | 2026-10-14 | 🟢 | Fixed in source | [Report](#17-conditional-blocks-do-not-mount-after-a-later-state-change) |
| Static and dynamic class merge | 2026-10-14 | 🟢 | Fixed in source | [Report](#18-dynamic-class-binding-replaces-static-classes) |
| CSP expression fallback | 2026-10-12 | 🟢 | Fixed in source | [Report](#8-runtime-expression-fallbacks-require-unsafe-eval) |
| Scoped CSS descendant selectors | 2026-10-12 | 🟢 | Fixed in source | [Report](#10-bare-element-selectors-emit-invalid-css) |
| Dynamic style under CSP | 2026-10-12 | 🟢 | Fixed in source | [Report](#12-dynamic-style-binding-is-blocked-by-strict-csp) |
| App import map under CSP | 2026-10-12 | 🟢 | Fixed in source | [Report](#13-generated-app-import-maps-are-blocked-by-strict-csp) |
| Repeated rows duplicate | 2026-10-12 | ✅ | Fixed in released 0.1.1 | [Report](#7-reactive-for-loops-append-duplicate-entries) |
| Conditional inside loop | 2026-10 | ✅ | Fixed in released 0.1.1 | [Report](#1-conditional-nodes-inside-loops-lose-loop-local-scope) |
| Global CSS escape | 2026-10 | ✅ | Fixed in released 0.1.1 | [Report](#4-scoped-css-does-not-provide-a-working-global-escape) |
| Validation allocator leak output | 2026-10 | ✅ | Fixed in released 0.1.1 | [Report](#6-successful-validation-reports-allocator-leaks) |
## Local fixes verified (2026-11-02)

- **Ceiv findings follow-up (2026-11-06):** current source emits boolean `aria-*` bindings as the strings `"true"` and `"false"`; a jsdom tab fixture checks both states before and after a click. Template literals in custom-component props now resolve embedded bindings during initial mount and later prop updates; a fixture covers the reported `` `help-${props.id}` `` expression. Child update regions now skip absent component handles, and destruction clears the handle; a nested conditional fixture covers hidden prop changes, mount, destroy, and remount. These tests establish browser DOM behavior. The original packaged Ceiv accessibility tree and previously failing conditional layout have not been rerun.
- **HTML void tags:** current source treats standard HTML void elements as self closing, including bare `<input>`, `<br>`, and `<img>`. `test/component/html-void-tags.test.ts` compiles and mounts the original nested label/input pattern plus sibling void tags with Zig 0.16.0 and Bun 1.2.16. Published packages remain unverified; location quality for unrelated mismatched closing tags is a separate diagnostics concern.
- **HTML entities in static templates:** current source decodes semicolon-terminated named HTML entities from the Python standard library HTML5 table and decimal/hex numeric references when emitting static text and attributes. `test/component/html-entities.test.ts` mounts `&amp;`, `&copy;`, `&mdash;`, a numeric emoji, and an unknown entity, checking rendered text and a `title` attribute. Published packages remain unverified; semicolonless legacy references are not yet supported.
- **Malformed TypeScript diagnostics:** current source halts after script analysis when the parser reports an error. Oxc's labeled span is carried into the compiler diagnostic, and the CLI exits nonzero instead of emitting an empty setup. The exact missing `)` pattern from the CC GUI report is covered by `zig build test` and `node test/package/malformed-script.test.mjs` with Zig 0.16.0 and Node 22.22.1. Published packages remain unverified.
- **Compound loop scoping retest:** `test/component/compound-scope.test.ts` mounts the recorded `workspace.children.length || pendingFor(workspace.id).length` condition and `props.view.locked || props.actions.text(workspace.id)` text under a loop. Both resolve in current source without a code change. This narrows the older CC GUI report to a historical version or a more specific expression shape; its original app has not been rerun.
- **Source checkout binary selection:** `platform.mjs` recognizes when the adapter runs from this Weiv checkout and selects its `zig-out/bin/weiv`; `WEIV_BINARY_PATH` still has priority. `node test/package/platform.test.mjs` verifies source and built adapter paths plus the override on Node 22.22.1. A missing checkout binary now reports that the source build is needed instead of silently selecting a published compiler. Published packages remain unchanged until release.
- **Template globals:** current source resolves common JavaScript globals such as `Math` and `String` when no component binding supplies them. A jsdom mount verifies `Math.round` before and after a click, `String(item.id)` inside a repeated input, and a component binding named `Math` taking precedence. Run `PATH=<Zig 0.16 directory>:$PATH bun test test/component/template-globals.test.ts`. Published packages remain unverified.
- **Inline SVG namespace:** current source emits SVG elements with `createElementNS`, carries the namespace through conditional and loop fragments, and uses HTML for children of `foreignObject`. A jsdom mount checks `svg`, `path`, and a conditional `circle` namespace, `viewBox` casing, and an HTML child. Run `PATH=<Zig 0.16 directory>:$PATH bun test test/component/svg-namespace.test.ts`. Published packages remain unverified.
- **Tracked array methods:** current source no longer proxies functions read from tracked objects. A mounted component using `props.items.map(...)` and `props.items.filter(...)` now renders with Zig 0.16.0 and Bun 1.2.16 (`PATH=<Zig 0.16 directory>:$PATH bun test test/component/array-methods.test.ts`). This addresses the proxy `prototype` failure recorded below; published packages remain unverified. The generated runtime change is in `src/compiler/backend/browser/emit/js_module/runtime_prelude.zig`.
- **Vite sibling imports:** the plugin now resolves a relative generated `.mjs` import from a `.weiv` component to a sibling `.weiv` source when that file exists. `node test/package/vite-plugin.test.mjs` builds an importing parent and child with Vite 5.4.21 on Node 22.22.1. The published package remains unverified.
- **Chained template calls:** direct template text `{{ props.items.map(item => item.name).join(separator) }}` initially emitted invalid JavaScript by rewriting the arrow parameter to `scope.item`. The expression emitter now recognizes a call suffix after the callback, preserves its local parameter, and resolves suffix arguments from scope. The mounted array-methods fixture renders both this expression and `filter(...).length` with current source. Published packages remain unverified.

## Cross-repository gap audit (2026-10-31)

This audit compares the local Atelier, Framecept, Lightcept, CC GUI, and Harngine Quest/Hearth reports with this ledger at Weiv commit `05c5024` (`weivjs` package version `0.1.2`). Existing entries below retain their original observation dates and release-specific claims. Source inspection verifies the current adapter and package behavior noted here; historical browser observations are not presented as fresh runtime reproductions.

| Finding | Current assessment | Evidence |
| --- | --- | --- |
| Generated sibling `.mjs` imports in Vite | **Fixed in current source; release unverified** | The 2026-11-02 Vite build above bundles a parent and sibling child component. Published-package observations below retain their original release scope. |
| Source-linked adapter selects a published platform binary | **Fixed in current source; release unverified** | The 2026-11-02 platform test above verifies source checkout detection and explicit override through source and built adapter paths. |
| Type-only imports in generated setup | **Fix present in uncommitted source; release unverified** | The existing source follow-up below records the setup filter and Zig test. The checkout has pending edits to `setup.zig` and `e2e_test.zig`; this audit does not call the fix released. |
| Top-level `const` assignment | **Fixed in published 0.1.2 by the recorded minimal mount check** | The CC GUI reproduction and verification below establish the release boundary. |
| Quest `String(...)` template global | **Fix verified in current source; release unverified** | The Quest source report records the 0.1.0 failure. The 2026-11-02 local mount test above verifies `String(item.id)` in a repeated input and `Math.round(...)` in template text. |
| Quest reserved label `for` and directive syntax | **Historical 0.1.0 gap; superseded by symbol directives** | Existing Hearth and repository follow-ups below cover the `#for` migration and native label behavior. |
| Repeated-card async delay in Quest | **Unisolated observation** | The Quest report has no minimal reproduction separating event scope, async updates, and polling; it does not establish a distinct Weiv defect. |

### Template global `String` in Quest 0.1.0

- **Classification:** confirmed historical template-expression failure in published `weivjs@0.1.0`; current-source and 0.1.2 behavior not verified.
- **Context:** Harngine Quest `apps/quest/src/ui/App.weiv`, macOS, Bun 1.2.16, TypeScript 5.9.3, Node 24.21.0. Source: `daydream/projects/harngine/docs/archive/implementation/2026-10-quest-weiv-friction.md`.
- **Reproduction:** use `bind:value="String(item.id)"` inside a repeated template item and compile with the 0.1.0 CLI; mount and update the loop.
- **Expected:** the global `String` call converts the item ID, or compilation identifies an unavailable template binding.
- **Actual:** emitted client code calls `scope.String(item.id)` and update throws `TypeError: scope.String is not a function`.
- **Workaround:** bind `item.id` directly and rely on the binding emitter's string coercion. The current `Math` report below is related, but does not prove that `String` has the same behavior in 0.1.2.

### Source-linked Vite adapter can select an older compiler binary

- **Classification:** confirmed current source/binary selection behavior; local development tooling gap, not a compiler defect.
- **Context:** Framecept uses `file:../../../weiv/packages/weiv`, macOS, Node 26.6.0, Vite 7.3.7, TypeScript 5.9.3, Tauri 2.12.3, Zig 0.16.0. Source: `/Users/chao.yang/Private/framecept/WEIV_FRICTION.md`.
- **Reproduction:** install the local package while an older `@weivjs/weiv-darwin-arm64` optional dependency is installed, rebuild the sibling `zig-out/bin/weiv`, and run `vite build` without `WEIV_BINARY_PATH`.
- **Expected:** the linked adapter and compiler use the same source revision, or report the version mismatch.
- **Actual:** `resolveWeivBinaryPath()` in `packages/weiv/src/platform.mjs` resolves the published optional package first. The current source still follows this path. This can make adapter fixes available while compiler fixes are absent.
- **Workaround:** set `WEIV_BINARY_PATH` to the sibling `zig-out/bin/weiv`; Framecept's Vite configuration does so when that binary exists, while preserving an explicit environment override.

## CC GUI reactive array `.filter` proxy failure in 0.1.1 (2026-10-28)

- **Classification:** confirmed runtime defect in an existing `weivjs@0.1.1` Vite dev server; direct `.filter` behavior under 0.1.2 remains untested.
- **Context:** CC GUI `CommandPalette.weiv` search fixture, macOS arm64, Node 22.22.1, Vite 6.4.3.
- **Reproduction:** mount a component with an array prop `commands` and an `@input` handler that assigns `filtered = props.commands.filter(c => c.title.includes(query))`; type into the input.
- **Expected:** the rendered list narrows to matching commands.
- **Actual:** `TypeError: 'get' on proxy: property 'prototype' is a read-only and non-configurable data property on the proxy target but the proxy did not return its actual value`, thrown from `Proxy.filter`; the list does not update.
- **Workaround:** use `for…of` over the prop, collect matches in a new plain array, and assign the array to the tracked list. This rendered the matching row under 0.1.1 and a separately served published-0.1.2 build without console errors. Retest direct `.filter` on 0.1.2 before treating it as a current defect.

## Published 0.1.2 emits type-only import as runtime binding (2026-10-28)

- **Classification:** confirmed compiler defect in published `weivjs@0.1.2`; checkout `355153dae17b345094bbe6ba269dc8b01a43cddb` not retested.
- **Context:** CC GUI `Button.weiv` mechanical port, macOS arm64, Node 22.22.1, Vite 6.4.3.
- **Reproduction:** put `import { buttonClass, type ButtonSize } from "./button-visual.ts";` in a `.weiv` script, use `ButtonSize` only as a prop type, compile via the 0.1.2 CLI or Vite adapter, then mount.
- **Expected:** type-only import is erased and mount succeeds.
- **Actual:** generated setup references `__weiv_import_ButtonSize`; mount throws `ReferenceError: __weiv_import_ButtonSize is not defined` at `Button.weiv` setup. Compiler and TypeScript checker did not flag it.
- **Workaround:** import only runtime functions and declare the union type locally in the `.weiv` script. The CC GUI button matrix then mounted and matched React geometry and computed styles in light and dark fixtures.

## Published Vite adapter does not resolve generated sibling component imports (2026-10-28)

- **Classification:** confirmed `weivjs@0.1.1` and `0.1.2` Vite adapter gap; current checkout `355153dae17b345094bbe6ba269dc8b01a43cddb` not yet retested.
- **Context:** fresh CC GUI `KbdSlotFixture.weiv` importing sibling `Kbd.weiv`, Vite 6.4.3, macOS arm64, Node 22.22.1.
- **Reproduction:** in a `.weiv` script import `Kbd` from `./Kbd.weiv`, render `<Kbd><span>⌥</span></Kbd>`, and serve through `weivjs/vite`.
- **Expected:** Vite resolves and transforms the child component.
- **Actual:** compiler emits `import * as Kbd from "./Kbd.mjs"`; Vite reports `Failed to resolve import "./Kbd.mjs" from "src/weiv-fresh/KbdSlotFixture.weiv"` and preview content disappears. The published 0.1.2 adapter source still has no generated sibling `.mjs` resolver; the project build passed with the workaround.
- **Workaround:** CC GUI Vite `resolveId` maps generated sibling `.mjs` imports back to existing `.weiv` sources. The child slot then rendered and matched the React reference in browser content and geometry.

## Template-bound `const` fails at mount in published 0.1.1 (2026-10-28)

- **Classification:** confirmed compiler defect in published `weivjs@0.1.1`, fixed in published `0.1.2` (minimal fixture compiled and mounted).
- **Context:** fresh CC GUI `Kbd.weiv` preview on macOS arm64, Node 22.22.1, Vite 6.4.3.
- **Reproduction:** compile `<template><kbd :class="kbdClass">K</kbd></template><script>const kbdClass = "h-5";</script>` with `weiv compile emit js Component.weiv > /tmp/component.mjs`, import it, and call `mount` with a DOM target.
- **Expected:** the constant supplies the class and mount succeeds.
- **Actual:** generated `setup` assigns `kbdClass = __weiv_getTrackedRoot("kbdClass", kbdClass);`; mount throws `TypeError: Assignment to constant variable.` Compilation and Vite build do not flag it.
- **Workaround:** use `let kbdClass`; the CC GUI fixture then mounted and updated in jsdom.

## Published 0.1.2 lists unavailable optional platform packages (2026-10-28)

- **Classification:** package distribution gap outside the tested macOS arm64 host.
- **Context:** `weivjs@0.1.2` npm registry metadata; CC GUI build passed with available `@weivjs/weiv-darwin-arm64@0.1.2`.
- **Reproduction:** read `npm view weivjs@0.1.2 optionalDependencies --json`, then query `npm view @weivjs/weiv-darwin-x64@0.1.0 dist.integrity --json`, `@weivjs/weiv-linux-x64-gnu@0.1.0`, and `@weivjs/weiv-linux-arm64-gnu@0.1.0`.
- **Expected:** each declared optional platform package resolves for its host.
- **Actual:** npm returns `E404 Not Found` for Darwin x64 and both Linux packages. Darwin arm64 and Windows x64 0.1.2 packages exist. Other-platform installation was not tested.
- **Workaround:** continue macOS arm64 integration; keep other platforms unverified until packages or declarations are updated.

## Noninteractive pnpm verification in CC GUI workspace (2026-10-28)

- **Classification:** project/tooling friction, not established as a Weiv defect.
- **Context:** pnpm 10.29.3, Node 22.22.1, existing CC GUI `node_modules`.
- **Reproduction:** run `pnpm exec vite build` from a non-TTY command session in the CC GUI Weiv migration workspace.
- **Expected:** installed Vite executes.
- **Actual:** pnpm exits before compilation with `[ERR_PNPM_ABORTED_REMOVE_MODULES_DIR_NO_TTY] Aborted removal of modules directory due to no TTY` during its dependency status check.
- **Workaround:** invoke installed binaries directly: `./node_modules/.bin/vite` and `./node_modules/.bin/tsc`.

## Lockfile-only Weiv dependency update rejected by CC GUI trust policy (2026-10-28)

- **Classification:** project/tooling blocker to normal lockfile regeneration, not a Weiv defect.
- **Context:** upgrading the fresh CC GUI preview to `weivjs@0.1.2`, pnpm 10.29.3, Node 22.22.1, macOS arm64.
- **Reproduction:** run `CI=true pnpm add -D weivjs@0.1.2 --lockfile-only --ignore-scripts` in CC GUI.
- **Expected:** package and lockfile update.
- **Actual:** `[ERR_PNPM_TRUST_DOWNGRADE]` rejects existing `semver@6.3.1` and `undici-types@6.21.0` entries; pnpm writes nothing.
- **Workaround:** pin `weivjs@0.1.2` and update only its package/importer/snapshot lock metadata using npm registry integrity hashes for available platform packages. No policy was relaxed. Clean-install validation remains pending a policy-approved dependency refresh.

## Published 0.1.1 external callbacks require `queueMicrotask` (2026-10-27)

- **Classification:** released-package/version documentation gap. The latest guide now distinguishes current-source `weivUpdate` from the published 0.1.1 workaround.
- **Context:** CC GUI command palette, `weivjs@0.1.1`, local Weiv checkout `1633af0`, macOS arm64, Node 22.22.1, pnpm 10.29.3, Vite 6.4.3.
- **Reproduction:** in `src/weiv/CommandPalette.weiv`, register a window `keydown` listener from a queued initialization and call `weivUpdate(togglePalette)` for Ctrl+K. Run the Vite fixture at `http://localhost:1420/tests/browser/weiv-timeline-search.html`, focus the page, and press Ctrl+K.
- **Expected:** the latest `packages/weiv/README.md` says published 0.1.1 must schedule external state changes through its wrapped `queueMicrotask`; current source supports `weivUpdate`.
- **Actual:** the fixture accessibility tree shows `ReferenceError: weivUpdate is not defined` with the generated handler at `CommandPalette.weiv`, and the palette does not open.
- **Workaround:** use `queueMicrotask(() => { togglePalette(); })` for window listeners and the same wrapper for registry subscriptions. The browser fixture then opened the palette with Ctrl+K, filtered commands, updated from a dynamically registered command, executed local and registered commands, navigated with arrows, wrapped Tab focus, and closed with Escape.
- **Upgrade check:** when moving to a package that provides `weivUpdate`, replace the 0.1.1 microtask workaround and retest native WKWebView.

## Native WKWebView accessibility exposes only the first command option (2026-10-27)

- **Classification:** WKWebView/Weiv accessibility interoperability gap; browser behavior is correct and the root cause is not yet isolated.
- **Context:** CC GUI command palette, packaged `CC GUI Weiv Preview.app`, `weivjs@0.1.1`, macOS arm64.
- **Reproduction:** build the isolated preview, launch it, focus the Weiv web content, press Cmd+K, and inspect the native macOS accessibility tree. The screenshot visibly contains Open Settings, Search chats, New chat, Toggle Files panel, Toggle Changes panel, Toggle terminal, Split right, Split down and Exit split view.
- **Expected:** every visible option with `role="option"` is exposed as a native accessibility child.
- **Actual:** the full native tree lists the dialog and a list containing only `text Open Settings`; the remaining visible buttons are absent from the accessibility tree. The Chrome browser fixture exposes every option. Keyboard ArrowDown plus Enter still runs the second visible command and Escape still closes the palette, so mouse and keyboard behavior works despite the tree omission.
- **Workaround:** none applied. Native keyboard operation remains available; a future cleanup should replace the list container/button structure with an accessibility arrangement verified by macOS VoiceOver.

## Nested Git row template expression scoping (2026-10-27)

- **Classification:** compiler/template-expression issue; precise minimal root cause not yet isolated.
- **Context:** CC GUI Weiv Changes panel, `weivjs@0.1.1`, Weiv checkout `1633af0`, macOS arm64, Node 22.22.1, pnpm 10.29.3, Vite 6.4.3.
- **Reproduction:** in `GitChanges.weiv`, nest `#for="row in group.rows"` inside `#for="group in props.view.groups"`; inside the row use conditions such as `#if="row.isDir"` and a computed attribute `:style="'padding-left:' + (row.depth * 14) + 'px'"`. Run `corepack pnpm build`, then open `tests/browser/weiv-timeline-search.html?manyChanges=1` and open Changes.
- **Expected:** the mounted directory/file rows render with their indentation.
- **Actual:** the build passed, but the Weiv error boundary showed `ReferenceError: row is not defined`, and the Changes body was partially rendered.
- **Workaround:** project `indentStyle` and `groupId` as simple row properties in `git-changes-view.ts`, then bind `:style="row.indentStyle"` and `:data-group="row.groupId"`. The 2,000-file browser fixture then showed bounded rows and worked on deep scroll. This narrows the problem to template expression or nested-loop scoping but does not prove which expression caused the error.

This report records reproducible Weiv integration and tooling friction. No
external issue has been submitted.

## External event listener ownership (2026-10-21)

- **Classification:** confirmed compiler analysis defect, fixed in current source.
- **Context:** `.weiv` component with local state, macOS arm64, Zig 0.16.0,
  Bun 1.2.16, Weiv checkout based on `8470b95`.
- **Reproduction:** in a component script, register
  `window.addEventListener("change", () => { count += 1; })` and render
  `{{ count }}`. Dispatch the event after mounting.
- **Expected:** the analyzer marks this callback unowned or the runtime wraps
  it so the text updates.
- **Actual:** the Rust analyzer marked every `.addEventListener` callback as
  owned, while the generated component did not wrap script-registered listeners.
  The DOM kept the prior count after dispatch. There was no build error output.
- **Fix and workaround:** the analyzer now marks these listeners unowned.
  Place the mutation inside `weivUpdate(() => { count += 1; })` to flush it.
  A DOM regression and analyzer test cover both behaviors.

## Compiler toolchain selection (2026-10-21)

- **Classification:** tooling and documentation gap, not a confirmed compiler defect.
- **Context:** checking a browser backend file-organization refactor at the
  current checkout. macOS arm64, Bun 1.2.16, Homebrew Zig 0.17.0 on `PATH`.
- **Reproduction:** run `zig build test` from the repository root with Zig
  0.17.0. `bun test test/inspect` reaches the same build error because its
  tests invoke the compiler through `zig build`.
- **Expected:** the repository states or selects the Zig version needed to
  build it, and the documented test command uses that version.
- **Actual:** `build.zig:51:11: error: no field named 'args' in struct 'Build'`
  (`/opt/homebrew/Cellar/zig/0.17.0/lib/zig/std/Build.zig:1:1: note: struct declared here`).
- **Workaround:** install Homebrew `zig@0.16` and run
  `PATH=/opt/homebrew/opt/zig@0.16/bin:$PATH zig build test`. This passed.
  The mismatch is reproducible; no Weiv source change is needed for this refactor.

The following sections record friction found while building the interactive
Roam, Muse, and Hearth demos with Weiv.

## Environment

- Task: build a browser UI that completes the Roam workflow end to end.
- App component: `apps/roam/src/ui/App.weiv` (648 lines, 32,226 bytes).
- Weiv package: `weivjs@0.1.0`.
- Weiv source inspected at commit: `94c330880876969c3dd414c62ad8fad05d6a48ff`.
- Node.js: `v22.22.1`.
- Bun: `1.2.16`.
- Zig: `0.16.0`.
- OS: macOS `26.6.2` (`25G83`), Apple Silicon.

## Summary

| Finding | Fixing status | Classification | Impact | Workaround used |
| --- | --- | --- | --- | --- |
| `if` nested in `for` uses the wrong ref scope | **Fixed in 0.1.1** | Confirmed code-generation/runtime defect | Later list entries and following UI can disappear | Replace the conditional node with text/class bindings |
| State assigned after `await` does not refresh immediately | **Fixed in 0.1.1; original app not rerun** | Async boundary limitation or documentation gap | Server changes succeed but the visible UI remains stale | Apply post-`await` changes inside `queueMicrotask` |
| `bind:value` is not two-way despite two-way-binding terminology | **Resolved by documentation in 0.1.1** | API naming/documentation gap | Forms submit stale component state | Add an explicit `on:input` handler |
| `:global(...)` is emitted as scoped CSS | **Fixed in 0.1.1** | Missing capability or compiler defect | Root variables and body styles do not apply | Scope variables to the app and put shell CSS in the host page |
| Full-app emit/package-runner builds were killed | **Open — environment-sensitive, not reproduced** | Tooling/resource interoperability issue | Normal package scripts could not reliably build this component | Invoke split JS/CSS compilation with the direct shell script |
| Successful validation prints allocator leak errors | **Fixed in 0.1.1** | Confirmed tooling defect | Clean CI output is impossible and a real leak may be hidden | None; command still exits zero |
| Reactive `for` updates duplicate entries in Muse | **Fixed in 0.1.1; current-source regression added** | Confirmed in published 0.1.0 runtime | A changing constellation corrupts its DOM | Render fixed-cardinality nodes explicitly |
| Runtime expression fallbacks require `unsafe-eval` | **Fixed in current source; unreleased** | Security/tooling incompatibility | Strict-CSP apps fail when an expression cannot be compiled directly | Use directly rewritable expressions or named handlers |
| Native label `for` is parsed as a loop | **Fixed in 0.1.1** | HTML interoperability/documentation gap | Standard label association does not compile | Nest the control inside the label |
| Bare element selectors lose the descendant combinator | **Fixed in current source; unreleased** | Confirmed CSS-emission defect in `weivjs@0.1.0` | Emitted CSS is invalid | Narrow post-compile repair |
| Current docs and installed directive syntax differ | **Resolved in 0.1.1 and weiv.dev** | Documentation/version discoverability gap | Compilation succeeds but structural regions all render | Use the installed package's compatibility syntax |
| Dynamic style binding is blocked by strict CSP | **Fixed in current source; unreleased** | Weiv/CSP interoperability defect | Dynamic layout declarations have no effect when inline styles are disallowed | Use scoped classes |
| Generated app import maps are blocked by strict CSP | **Fixed in current source; unreleased** | Weiv/CSP bundling incompatibility | Apps with bare imports fail to resolve their dependencies | Allow the inline import map or bundle/rewrite bare imports |
| Vue structural syntax is accepted as inert HTML | **Fixed in current source** | Migration/tooling diagnostics gap | A list or conditional silently renders once as static markup | Replace `v-for`/`v-if` with `#for`/`#if` and verify the packaged UI |
| Loop event expressions resolve component functions from loop scope | **Fixed in current source; browser regression passes** | Confirmed in published 0.1.1 runtime | Per-item actions silently do nothing | Decorate each item with a callback and explicitly invoke it |
| Async list-item updates do not refresh repeated bindings | **Fixed in current source for declared async helpers** | Confirmed async reactivity defect in `weivjs@0.1.1` | Asynchronously enriched item attributes remain stale | Update the model and the rendered element, or route scalar writes through a synchronous helper |
| Conditional blocks do not mount after later state changes | **Fixed in current source; exact Framecept regression passes** | Confirmed in the earlier Framecept integration state | Inspectors and empty states remain stuck in their initial branch | Keep both states mounted and toggle visibility synchronously |
| Dynamic class binding replaces static classes | **Fixed in current source** | Confirmed attribute-merging defect in `weivjs@0.1.1` | Base styling disappears when the binding updates | Return the complete class string from one binding |

## 1. Conditional nodes inside loops lose loop-local scope

**Fixing status:** Fixed in `0.1.1` and covered by a browser regression.

### Minimal pattern

```html
<article #for="strategy in data.strategies">
  <h3>{{ strategy.title }}</h3>
  <i #if="strategy.id === data.brief.selectedStrategyId">✓</i>
</article>
```

### Reproduction

1. Render a list containing at least two strategies.
2. Put an `if` node inside the repeated element, with a condition that reads the
   loop item.
3. Compile and mount the component.

### Expected

Every strategy renders, and the mark appears only on the selected strategy.

### Actual

The first entry rendered, then later entries and subsequent page sections were
missing. In generated JavaScript, the loop creates entry-local refs, but the
conditional updater reads the component's root `instance.refs`. Removing the
nested conditional restored the complete page.

### Workaround

Keep the node mounted and bind its content and visibility instead:

```html
<i :class="'selected-mark' + (strategy.id === selectedId ? ' visible' : '')">
  {{ strategy.id === selectedId ? "✓" : "" }}
</i>
```

This appears to be a compiler/runtime defect, not a project incompatibility.

## 2. Post-`await` state changes occur outside the reactive boundary

**Fixing status:** Fixed in `0.1.1` and covered by an async mutation regression;
the original Roam request sequence was not rerun because its fixture is absent.

### Minimal pattern

```ts
async function load() {
  const next = await api("/api/state");
  data = next;
}

async function selectStrategy(id: string) {
  busy = true;
  await api("/api/select", { strategyId: id });
  await load();
  busy = false;
}
```

### Reproduction

1. Trigger `selectStrategy` from a Weiv event handler.
2. Confirm that the API response contains the new selected strategy.
3. Observe the selection indicator without reloading the page.

### Expected

Assignments after `await` invalidate dependent bindings and update the DOM.

### Actual

The backend state changed, but the selected strategy and busy state stayed stale
until a full reload. The generated event boundary completes synchronously when
the handler returns its Promise; later assignments therefore run outside that
boundary.

### Workaround

Schedule the state application through a wrapped asynchronous primitive:

```ts
const next = await api("/api/state");
queueMicrotask(() => applyState(next));
```

The UI then updates immediately. If async event handlers are intentionally not
tracked, this needs prominent documentation and a first-class recommended
pattern; otherwise it is a runtime defect.

## 3. `bind:value` is one-way despite two-way-binding terminology

**Fixing status:** Resolved as a documentation/API-expectation issue in `0.1.1`;
one-way binding remains intentional.

### Minimal pattern

```html
<input :value="draftOrigin" />
```

### Reproduction

1. Initialize `draftOrigin` from component state.
2. Edit the input in the browser.
3. Submit a form that reads `draftOrigin`.

### Expected

The edited input value is reflected in `draftOrigin`, as the `bind:value`
spelling commonly implies.

### Actual

The visible input changed, but the submitted value remained the initial value.
Weiv examples pair `bind:value` with explicit input/change handlers, but the
quick-start material did not make the one-way semantics clear.

### Workaround

```html
<input :value="draftOrigin" @input="updateOrigin" />
```

```ts
function updateOrigin(event: Event) {
  draftOrigin = (event.currentTarget as HTMLInputElement).value;
}
```

This may be intentional API behavior, but the directive name and missing
explanation caused avoidable integration time.

## 4. Scoped CSS does not provide a working `:global(...)` escape

**Fixing status:** Fixed in `0.1.1` with compiler regression coverage.

### Minimal pattern

```css
:global(:root) {
  --ink: #193047;
}

:global(body) {
  margin: 0;
}
```

### Reproduction

1. Put the CSS above in a `.weiv` component.
2. Emit the component CSS.
3. Inspect the generated selectors and load the page.

### Expected

The compiler emits `:root` and `body`, or documents another supported way to
write global shell styles.

### Actual

The output retained `:global(...)` behind the component scope, for example:

```css
[data-weiv-scope="..."]:global(:root),
[data-weiv-scope="..."] :global(:root)
```

Browsers did not apply the rules, so CSS variables fell back and the page lost
its intended color system.

### Workaround

Define variables on the scoped app root and keep the small `html`, `body`, and
mount-point reset in the host page. This works, but splits component styling
across two sources.

## 5. Full-app emit and package-runner builds were killed

**Fixing status:** Open. The failure appears environment-sensitive and has not
been reproduced without the original Roam fixture.

### Reproduction A: full-app emit

```sh
node_modules/.bin/weiv compile emit app apps/roam/src/ui/App.weiv /tmp/output
```

When invoked through the original Bun package script, the result was:

```text
$ weiv compile emit app src/ui/App.weiv public
error: script "build:ui" was terminated by signal SIGKILL (Forced quit)
```

### Reproduction B: split compilation under a package runner

The split compiler commands work when the script is executed directly, but the
same script under `bun run` was killed:

```text
scripts/build-ui.sh: line 10: 54082 Killed: 9 "$compiler" compile emit js "$package_directory/src/ui/App.weiv" > "$output_directory/App.mjs"
error: script "build:ui" exited with code 137
```

### Expected

A 32 KB component compiles through the documented full-app path and ordinary
package scripts without being terminated.

### Actual

Full-app emit was killed. Split JS/CSS compilation succeeded only when the shell
script was invoked directly. Another Zig process was consuming substantial
memory during part of the investigation, so this finding may be
environment-sensitive and should not yet be labeled a deterministic Weiv bug.

### Workaround

The checked-in build path is:

```sh
sh apps/roam/scripts/build-ui.sh
```

It emits JavaScript and CSS separately and has been reliable in this workspace.

## 6. Successful validation reports allocator leaks

**Fixing status:** Fixed in `0.1.1`; validation now frees transferred
diagnostics without allocator leak output.

### Reproduction

```sh
node_modules/.bin/weiv compile validate app apps/roam/src/ui/App.weiv --json
```

### Expected

The validator exits zero with JSON diagnostics and no allocator errors.

### Actual

The command exits `0`, reports `"ok": true`, and then writes the following
complete allocator error output (addresses vary between runs):

```text
error(gpa): memory address 0x104fe0640 leaked:

error(gpa): memory address 0x104fe0660 leaked:

error(gpa): memory address 0x104fe0680 leaked:

error(gpa): memory address 0x104fe06a0 leaked:

error(gpa): memory address 0x1005630c0 leaked:

error(gpa): memory address 0x100563100 leaked:

error(gpa): memory address 0x100563140 leaked:

error(gpa): memory address 0x100563180 leaked:

error(gpa): memory address 0x104f53980 leaked:

error(gpa): memory address 0x104f53a80 leaked:

error(gpa): memory address 0x104f53b00 leaked:

error(gpa): memory address 0x104f53b80 leaked:

error(gpa): memory address 0x104f69000 leaked:
```

The local source compiler also emitted allocator leak diagnostics from paths
including `DiagnosticBag.appendOwned`, `appendBindingDiagnostics`,
`compileReport`, `Graph.collectValidated`, and `validateApp` while still
producing output. This is reproducible tooling noise and likely a real cleanup
defect.

## Result

None of these findings blocked the finished demo. With the workarounds above,
the UI supports trip creation, strategy selection, approval/hold creation, and
navigation without a reload.

## Repository follow-up (2026-10-11)

- Fixed nested structural regions by preserving the caller's ref scope through
  conditional and loop helpers. A browser regression covers initial rendering
  and an async state change for an `if` nested in a `for`.
- Confirmed that current owned-event boundaries flush again when a returned
  Promise settles. The regression mutates the selected item after `await`
  without using the reported `queueMicrotask` workaround. The original Roam app
  is not present in this checkout, so its exact request sequence was not rerun.
- Documented the intentionally one-way semantics of `bind:value` and the
  explicit input-event pattern in the package README.
- Fixed whole-selector `:global(...)` emission and added compiler coverage for
  global and ordinary scoped selectors in the same component.
- Reproduced validation leaks with `test/examples/kanib/App.weiv`. The app graph
  discarded the diagnostic slice while transferring a successful compile
  report, preventing its destructor from freeing those allocations. The
  transfer now frees diagnostics first; validation completes without allocator
  leak output.
- The full-app/package-runner SIGKILL report remains environment-sensitive and
  was not reproduced from the absent Roam fixture.

## Muse follow-up (2026-10-12)

### Environment

- Task: build Muse's interactive spatial constellation and guided Spark loop.
- App component: `apps/muse/src/ui/App.weiv` in the Harngine repository.
- Weiv package: `weivjs@0.1.0` (`@weivjs/weiv-darwin-arm64@0.1.0`).
- Node.js: `v22.22.1`.
- TypeScript: `5.9.3`.
- Browser: Chromium 155 embedded browser.
- OS: macOS arm64.

### 7. Reactive `for` loops append duplicate entries

**Fixing status:** Fixed in `0.1.1` by the nested structural ref-scope repair;
current-source real-DOM regression coverage also protects plain loop appends.

#### Minimal reproduction

```html
<template>
  <button for="node in nodes" on:click="select(node.id)">
    {{ node.title }}
    <i if="node.evidence.length > 0">{{ node.evidence.length }} trace</i>
  </button>
</template>
<script>
  let nodes = [{ id: "a", title: "A", evidence: ["hash"] }];
  let selected = "";
  function select(id) { selected = id; }
</script>
```

1. Compile with `weiv compile emit js App.weiv`.
2. Mount the emitted component.
3. Click the loop-rendered button so reactive state updates.

Expected: selection updates and the loop retains one DOM entry per array item.

Actual: the nested conditional update throws, and later dirty-region passes
append duplicate loop entries. A plain message `for` loop without a nested
conditional also appended a second copy when its backing array gained an item,
so the reconciliation issue is broader than the conditional crash:

```text
TypeError: Cannot read properties of undefined (reading 'parentNode')
    at replaceBetween (App.mjs:2:24)
    at updateConditional_* (App.mjs:983:5)
    at updateRegion_conditional_* (App.mjs:1971:3)
    at update (App.mjs:870:5)
    at createForEntry_* (App.mjs:919:3)
    at updateForLoop_* (App.mjs:937:16)
```

Workaround: Muse renders its eight known reference nodes explicitly. Its
conversation renders the latest exchange in a stable element. The append-only
lineage still uses `for` because it does not mutate while mounted. This prevents
a general dynamic constellation until stable keyed reconciliation is available.

This overlaps finding 1, which is fixed in the repository after 0.1.0. Retest
the broader plain-loop append case against the current source before closing it.

### 8. Runtime expression fallbacks require `unsafe-eval`

**Fixing status:** Fixed in current source; unreleased. Directly rewritable
calls such as `selectNode(node.id)` compile to ordinary JavaScript and execute
inside the owned reactive boundary. The emitter no longer includes the
`Function(...)` runtime evaluator: expressions that cannot be resolved by the
static paths fail emission instead of requiring `unsafe-eval`. The shared
resolver is used by text interpolation, attribute binding, structural regions,
child props, and DOM or child-component handlers; this is not limited to event
expressions.

- Classification: security/tooling incompatibility and documentation gap.
- Reproduction: compile `on:click="selectNode(node.id)"`, serve with
  `Content-Security-Policy: script-src 'self' 'unsafe-inline'`, and click it.
- Expected: emitted code calls the in-scope function without runtime code
  generation.
- Actual: emitted `__weiv_evaluate` calls `Function(...)`; Chromium blocks it
  because `unsafe-eval` is absent.

```text
EvalError: Evaluating a string as JavaScript violates Content Security Policy
    at Function (<anonymous>)
    at __weiv_evaluate (App.mjs:10:10)
```

Workaround: keep the strict CSP and expose named zero-argument handlers such as
`select0` and `select1`. Named handler references compile without runtime
evaluation. Muse does not weaken its CSP with `unsafe-eval`.

### 9. Native label `for` is parsed as a loop directive

**Fixing status:** Fixed in `0.1.1`; structural directives now require `#for`,
so bare `for` remains a native HTML attribute.

- Classification: HTML interoperability and diagnostics gap.
- Reproduction: add `<label for="seed-question">Question</label>` to a valid
  component.
- Expected: `for` is emitted as the native label/input association attribute.
- Actual: compilation halts with `template.invalid_directive` at an offset that
  does not identify the label. The compiler reserves every `for` attribute for
  loop syntax.
- Workaround: Muse nests the textarea inside its label so the accessible
  association remains intact. An explicit `htmlFor` or escaped-attribute form
  should be documented or supported for standard accessible forms.

## Hearth integration follow-up (2026-10-12)

### Environment

- Task: build Hearth's ambient home-world UI as a Weiv single-file component.
- Installed package: `weivjs@0.1.0`.
- Weiv source inspected at commit: `c06e21bdc13da4dde9907d66463a1c36b8710e49`.
- Node.js: `v22.22.1`.
- Bun: `1.2.16`.
- OS: macOS on Apple Silicon.
- App component: `harngine/apps/hearth/src/ui/App.weiv`.

### 10. Bare-element selectors emit invalid CSS

**Fixing status:** Fixed in current source with selector-list and pseudo-class
regressions; not yet released.

- Classification: confirmed compiler CSS-emission defect in the installed package.
- Minimal reproduction:

```weiv
<template>
  <header><button>Hello</button></header>
</template>

<style>
  button, input, textarea { font: inherit; }
  header { display: flex; }
</style>
```

Run from the Harngine workspace:

```sh
node_modules/.bin/weiv compile emit css apps/hearth/src/ui/App.weiv
```

Expected valid descendant selectors:

```css
[data-weiv-scope="…"] button,
[data-weiv-scope="…"] input,
[data-weiv-scope="…"] textarea { font: inherit; }
[data-weiv-scope="…"] header { display: flex; }
```

Actual output concatenates the scope attribute directly with the element:

```css
[data-weiv-scope="…"]button,
[data-weiv-scope="…"]input,
[data-weiv-scope="…"]textarea { font: inherit; }
[data-weiv-scope="…"]header { display: flex; }
```

Biome reports:

```text
expected `,` but instead found `button`
expected `,` but instead found `input`
expected `,` but instead found `textarea`
expected `,` but instead found `header`
expected `,` but instead found `aside`
expected `,` but instead found `main`
```

Workaround: `harngine/apps/hearth/scripts/build-ui.sh` performs a narrow post-compile repair. It
inserts the missing descendant combinator only between Weiv's generated scope attribute and the
affected bare HTML element selectors. The source remains a standard Weiv component.

### 11. Current documentation and installed directive syntax differ

**Fixing status:** Resolved by the `0.1.1` release and matching `weiv.dev`
documentation. Projects pinned to `0.1.0` must use that version's syntax.

- Classification: documentation/version discoverability gap.
- Expected from the inspected current source documentation: `#if`, `#for`, `:name`, and `@event`
  compile as structural directives, bindings, and handlers.
- Actual in the installed `weivjs@0.1.0`: compilation succeeds, but those spellings are emitted as
  literal DOM attributes, leaving every structural region visible at once.
- Workaround: use the installed package's compatibility spellings—`if`, `for`, `bind:name`, and
  `on:event`—which compile into the intended conditional regions, loops, bindings, and handlers.

A versioned syntax table or compiler diagnostic would expose the mismatch before browser testing.

### 12. Dynamic style binding is blocked by strict CSP

**Fixing status:** Fixed in current source; unreleased. The root cause was Weiv
writing a dynamic style binding with `setAttribute("style", value)`, which
Chromium rejects under Hearth's `style-src 'self'` policy. The emitter now uses
the CSSOM `element.style.cssText` setter. Chromium accepts that setter under the
same policy and the browser performs declaration parsing without Weiv needing a
second CSS parser.

- Classification: confirmed browser-visible binding defect in the installed package.
- Reproduction: bind a string such as `left:58%;width:60px` with
  `bind:style="bloomStyle(bloom)"`.
- Expected: the declarations appear in `element.style.cssText` and affect layout.
- Actual: `outerHTML` contains the expected `style` attribute text, but
  `element.style.cssText` is empty and the declarations do not affect layout. The same result was
  observed with CSS custom properties and ordinary declarations. Class and text bindings in the
  same loop update correctly.
- Workaround: keep dynamic meaning in class bindings, express the four seed-memory garden
  positions as scoped CSS classes, and use stable scoped CSS for weather visuals.

### Related compact-control handler finding

A `for` directive on Pulse preset buttons rendered the expected controls, but the argument-bearing
click handler did not update the bound input in browser QA. This overlaps Muse finding 8: named,
zero-argument handlers avoid runtime expression evaluation and work under the strict CSP. Hearth
therefore renders its four Pulse starters and five energy values explicitly with named handlers.

No external issue was submitted for these Hearth findings.

### 13. Generated app import maps are blocked by strict CSP

**Fixing status:** Fixed in current source; unreleased. App emission no longer
writes an inline `<script type="importmap">`. Bare imports are rewritten to a
same-origin `__weiv_packages` endpoint, and the generated Bun server resolves,
browser-bundles, and caches each requested package.

- Classification: confirmed Weiv/CSP bundling incompatibility.
- Reproduction: emit an app containing a bare import, serve its generated HTML
  with `Content-Security-Policy: script-src 'self'`, and load it in Chromium.
- Expected: the external application module and its dependencies load without
  requiring `unsafe-inline`.
- Actual: Chromium rejects the import map and reports
  `TypeError: Failed to resolve module specifier` when the bare import is used.
- Current-source verification: the generated HTML contains no inline import
  map, and an HTTP request to the generated server returned a browser-bundled
  workspace package with `Content-Type: text/javascript` and status 200.
- Custom static hosting must provide equivalent files for the rewritten package
  endpoint; the generated Bun server supplies it automatically.

## Repository follow-up (2026-10-12)

- Retested reactive generic loops against current source with a real DOM. A
  regression now selects an item through an argument-bearing loop handler,
  appends a fourth item, and verifies that all four keyed entries occur exactly
  once while the nested conditional remains stable. The broader duplication
  report was not reproduced after the nested structural ref-scope fix shipped
  in `0.1.1`.
- Confirmed a related owned-boundary defect for call-expression handlers.
  Current source already rewrote `@click="selectNode(node.id)"` directly and did
  not emit `Function(...)`, but it evaluated the call before entering
  `runOwnedBoundary`. The emitter now evaluates both DOM and child-component
  handler expressions inside the owned boundary, so their mutations flush and
  directly rewritable calls remain compatible with strict CSP.
- Confirmed that the canonical structural grammar in `0.1.1` leaves bare
  `for`, `if`, and `else` as ordinary HTML attributes. Native
  `<label for="...">` therefore compiles without an escape or workaround.
- Reproduced the bare-element CSS defect in current source. Root matches now
  insert the scope attribute after the type selector—for example,
  `button[data-weiv-scope="..."]`—while descendant matches retain the required
  space. Compiler coverage includes selector lists and a type selector with a
  pseudo-class.
- Published `weivjs@0.1.1` and updated `weiv.dev` document the canonical `:`,
  `@`, and `#` syntax plus the temporary `bind:`/`on:` compatibility warnings.
  The documentation mismatch remains relevant only when a project installs
  `0.1.0` while reading current docs.
- Retested dynamic `:style` against current source in jsdom. The declaration
  text appears in the attribute and in `element.style.cssText`, with parsed
  `left` and `width` values, but jsdom does not enforce Hearth's CSP. A minimal
  Chromium reproduction using `style-src 'self'` confirms the original symptom:
  `setAttribute("style", ...)` retains raw attribute text while the CSSOM stays
  empty. The same declarations applied with either `style.cssText` or
  `style.setProperty(...)` populate the CSSOM. Weiv now emits the `cssText`
  setter, preserving string-binding replacement semantics without manually
  decomposing declarations. Static `style="..."` template attributes now use
  the same CSSOM path instead of `setAttribute`.

## Framecept integration follow-up (2026-10-14)

### Environment

- Task: migrate the Framecept Qt desktop shell, media library, and timeline
  list to Weiv.
- Weiv source: sibling checkout at `/Users/chao.yang/Private/weiv`.
- Weiv package: `weivjs@0.1.1`.
- Node.js: `26.6.0`.
- Vite: `7.3.7`.
- TypeScript: `5.9.3`.
- Tauri: `2.12.3`.
- OS: macOS.

### 14. Vue structural syntax is accepted as inert HTML

**Fixing status:** Fixed in current source. The binder now emits targeted
`directive.vue_structural_syntax` warnings, and the Vite integration forwards
them during production builds. This was a migration diagnostic opportunity,
not a runtime defect. The current documentation correctly specifies `#for` and
`#if`.

#### Minimal reproduction

```html
<template>
  <li v-for="item in items">{{ item.title }}</li>
  <p v-if="items.length === 0">No items</p>
</template>
```

1. Add `v-for` or `v-if` to an element in a `.weiv` template.
2. Run the application's Vite production build (`vite build`).
3. Open the packaged application and inspect the affected list or conditional
   region.

Expected: the compiler or Vite integration reports a non-fatal migration
warning explaining that Vue structural syntax is an ordinary inert HTML
attribute in Weiv and that `#for` or `#if` is required.

Actual: the build succeeds without a warning or error. The element renders once
as static markup, so the mistake is discovered only while interacting with the
packaged UI. There is no error output to include because compilation exits
successfully.

Workaround: replace Vue-style attributes with Weiv structural directives and
verify the populated list or conditional state in the packaged application:

```html
<template>
  <li #for="item in items">{{ item.title }}</li>
  <p #if="items.length === 0">No items</p>
</template>
```

A targeted warning for the exact attribute names `v-for` and `v-if` would catch
a common migration error while preserving Weiv's general support for ordinary
custom HTML attributes.

### 15. Loop event expressions cannot resolve outer component functions

**Fixing status:** Fixed in current source; the published `weivjs@0.1.1`
behavior remains relevant. A real-DOM regression now invokes an
argument-bearing component helper from a generic loop and verifies the state
and nested conditional update.

#### Minimal pattern

```html
<button #for="asset in media" @click="addAssetById(asset.id)">
  Add to V1
</button>
```

```ts
async function addAssetById(id: number) {
  // Add the selected media asset to the timeline.
}
```

Expected: the click expression resolves the component-level function and
passes the current loop item's ID.

Actual: generated code calls
`loopScope.addAssetById(loopScope.asset.id)`. The repeated scope contains
`asset`, but not the outer component function, so clicking produces no state
change or visible diagnostic.

A related form, `@click="asset.addToTimeline"`, only evaluates the decorated
callback reference. It does not invoke the function and also produces no
visible diagnostic.

Workaround: decorate each loop item with a callback in component code and
explicitly invoke it from the event expression:

```ts
const decoratedMedia = media.map((asset) => ({
  ...asset,
  addToTimeline: () => addAssetById(asset.id),
}));
```

```html
<button #for="asset in decoratedMedia" @click="asset.addToTimeline()">
  Add to V1
</button>
```

This keeps every identifier resolved from the loop item while making the call
explicit. The finding is a confirmed event-scope defect, not a documentation
gap.

### 16. Async list-item updates do not refresh repeated bindings

**Fixing status:** Fixed in current source for component-declared `async
function` helpers. Reproduced with `weivjs@0.1.1`; this was a narrower case than
the post-`await` report in finding 2 because the async helper's Promise was
explicitly discarded by its caller.

#### Minimal pattern

```html
<img #for="asset in media" :src="asset.thumbnailUrl" alt="" />
```

```ts
async function loadThumbnail(asset: MediaAsset) {
  const url = await requestThumbnail(asset.id);
  media = media.map((candidate) =>
    candidate.id === asset.id ? { ...candidate, thumbnailUrl: url } : candidate,
  );
}
```

Expected: replacing the array after the host request refreshes the repeated
item's bound `src` attribute.

Actual: the generated async function leaves the assignment untracked, so the
model changes but the DOM retains the original attribute value. Scalar writes
after `await`, such as clearing a busy state, show the same behavior in this
integration.

Workaround: retain the model update and directly update the already-rendered
thumbnail after the host request resolves. For scalar assignments, routing the
write through a synchronous component function restores the reactive update.

This was a confirmed reactivity defect affecting async list enrichment. The
setup emitter now wraps declared async helpers in the component's owned
boundary, so completion is observed even when a caller uses
`void loadMissingThumbnails()`. A real-DOM regression replaces the array after
`await` and verifies the repeated image's `src` changes from `pending` to
`ready`.

### 17. Conditional blocks do not mount after a later state change

**Fixing status:** Fixed in current source. Originally reproduced with
`weivjs@0.1.1` at source commit
`87a52836c28a72dc72706c760483eefab76b7152`, plus the local scoped-CSS and event
fixes then present.

#### Minimal pattern

```html
<section #if="selectedId >= 0">Selected clip</section>
<section #if="selectedId < 0">No clip selected</section>
```

```ts
let selectedId = -1;

function selectClip(id: number) {
  selectedId = id;
}
```

1. Mount the component while `selectedId` is `-1`.
2. Assign a positive ID from a button click.
3. Run the Vite production build inside Tauri and select a clip.

Expected: the selected section mounts and the empty-state section unmounts.

Actual: adjacent text bindings update to the selected clip, but the structural
branches remain in their initial state. The initially false section stays
absent and the initially true empty-state section stays mounted.

Workaround: keep both inspector states mounted, toggle their visibility from a
synchronous selection helper, and update the timing text through the same
helper.

The exact Framecept shape now has real-DOM coverage: a callback stored on a loop
item selects a clip, the initially-false top-level conditional mounts, and the
inverse empty-state conditional unmounts. The current owned event-boundary
changes fixed this path; no additional structural emitter change was needed.

### 18. Dynamic class binding replaces static classes

**Fixing status:** Fixed in current source; reproduced in published
`weivjs@0.1.1`.

#### Minimal pattern

```html
<button class="clip" :class="selected ? 'selected' : ''">Clip</button>
```

Expected: the dynamic class is merged with the static class, producing either
`clip` or `clip selected`.

Actual: the generated binding replaces the complete `class` attribute. When
the expression evaluates to `selected`, the base `clip` class and its styling
are removed.

Workaround: return the complete class string from a single binding:

```html
<button :class="selected ? 'clip selected' : 'clip'">Clip</button>
```

This was a confirmed attribute-merging defect in `0.1.1`. Current source keeps
the static class tokens while applying and clearing the dynamic class value.

## Repository follow-up (2026-10-14)

- Added `directive.vue_structural_syntax` binder warnings for the exact
  attributes `v-if` and `v-for`. The Vite plugin now forwards non-fatal compiler
  warnings during its transform, and a production-build regression verifies the
  migration guidance reaches the user.
- Added static/dynamic class merging in the browser emitter. A real-DOM
  regression verifies `class="clip"` combined with a changing `:class` binding
  produces `clip`, then `clip selected`, then `clip` again.
- Retested `@click="selectStrategy(strategy.id)"` inside `#for` against current
  source. The component helper resolves through the loop scope and runs inside
  the owned boundary; the existing real-DOM regression verifies the selection
  and nested conditional update. No additional resolver change was needed.
- Added an exact Framecept reactivity fixture. It verifies that a loop-item
  callback mounts an initially-false top-level conditional and removes the
  inverse empty state; current event-boundary handling already passes this case.
- Wrapped component-declared async function helpers in the owned boundary at
  setup time. The same fixture calls a thumbnail loader with `void`, replaces
  its media array after `await`, and verifies the repeated `src` binding updates.
  Async arrow-function bindings are outside this specific repair and should be
  assessed separately if they exhibit the same fire-and-forget pattern.
- Removed the runtime `Function(...)` expression evaluator. The complete example
  corpus emits without it, preserving strict CSP without an `unsafe-eval`
  exception.
- Replaced inline app import maps with same-origin package URLs. The generated
  Bun server resolves and browser-bundles bare dependencies on demand, caches
  the result, and returns JavaScript without requiring `unsafe-inline`.

## Atelier integration findings (2026-10-27)

These findings were recorded in the local Atelier project while using published `weivjs@0.1.1` with Tauri 2 and Vite 7. The original observations below describe that package; current-source verification follows separately. The source report is `/Users/chao.yang/Private/atelier/WEIV_FRICTION.md`.

### Current-source verification (2026-10-27)

Retested against checkout `1633af0` with the fixes released in `weivjs@0.1.2`, Node 22.22.1, Vite 7.3.7, and Zig 0.16.0. These results do not establish what is available in the published `0.1.1` package. A fresh registry install of `0.1.2` confirmed that the packaged Mac compiler defines `weivUpdate`.

| Atelier finding | Current-source result |
| --- | --- |
| Top-level `const` reassignment | Reproduced; fixed by emitting a mutable internal binding for tracked locals. `node --check` passes. |
| Imported function called before initialization | Fixed by initializing imported aliases before user script execution. A top-level `listen` fixture mounts successfully. |
| Published Vite plugin omits CSS | Current plugin emits CSS. An additional relative `?weiv-style.css` import failure appeared in Atelier and was fixed in the plugin resolver. |
| Call-expression event handler misses update boundary | Focused `@click="selectEngine('codex')"` fixture updates the DOM. |
| Compound expression loses loop scope | Reproduced; fixed by resolving called helpers and loop items through the same scope. Focused fixture mounts and renders `Codex`. |
| `weivUpdate` unavailable in deferred callback | Focused deferred window-event fixture updates the DOM through `weivUpdate` in current source. Published `0.1.1` still emits an unresolved `weivUpdate` reference; its wrapped `queueMicrotask` works as a release-specific workaround. |
| Keyboard listener misses state flush | Direct external listeners need an update boundary. A current-source keyboard fixture works with `weivUpdate`, and a published `0.1.1` fixture works with its wrapped `queueMicrotask`. The package README now distinguishes those versions. |
| Invalid scoped global selectors | Current CSS emitter produces valid selectors for `*`, `body`, and `button`. |
| Conditional sibling loses loop scope | Focused two-message fixture renders both sibling branches correctly. |

The Atelier desktop and remote pages built with the local compiler and Vite plugin. The remote smoke test passed. The desktop smoke test passed after allowing one pending tracked-state microtask to run before closing jsdom; without that test-only wait, its assertions passed but a queued DOM update ran after `dom.window.close()`.

### Release-check binary detection false positive (2026-10-27)

- **Classification:** confirmed release-tooling defect, fixed in this checkout.
- **Context:** preparing `weivjs@0.1.2` on macOS arm64 with Node 22.22.1 and a Zig 0.16.0 `ReleaseFast` compiler binary.
- **Reproduce:** rebuild `packages/weiv-darwin-arm64/bin/weiv` from current source, then run `node tools/npm-release-check.mjs`.
- **Expected:** accept a real Mach-O binary and check only platform packages being published at the main package's version.
- **Actual:** the script decoded binary bytes as UTF-8 and rejected the real executable because embedded text contained `placeholder`. It also attempted to check older platform packages whose checked-in files are intentional placeholders.
- **Fix:** identify ELF, Mach-O, and PE binaries by magic bytes, then pack only platform packages matching the main package version. The release check now passes.

### Top-level `const` rewritten as an assignment

- **Category:** confirmed compiler defect in generated JavaScript; workaround available.
- **Context:** Tauri 2 + Vite 7 app using `weivjs` 0.1.1 on macOS, Node 22.22.1.
- **Reproduce:** place `const projectKey = "atelier.projects.v1";` in a `.weiv` component script and reference it from component logic. Run `npm run build`.
- **Expected:** generated module keeps a valid immutable binding or avoids reassigning it.
- **Actual:** Vite/Rollup reports `Cannot reassign a variable declared with const`. The transformed module contains `projectKey = __weiv_getTrackedRoot("projectKey", projectKey);`.
- **Workaround:** declare the binding with `let`. The build then completes without the warning.
- **Source:** `src/App.weiv`; generated output can be inspected through Vite at `/src/App.weiv?import` during development.

### Top-level call to an imported function runs before initialization

- **Category:** confirmed compiler defect in generated JavaScript; workaround available.
- **Context:** Atelier's Weiv 0.1.1 component imports `listen` from `@tauri-apps/api/event` and registers a listener at script top level. macOS Tauri 2 release webview; Vite 7, Node 22.22.1.
- **Reproduce:** add `import { listen } from "@tauri-apps/api/event";` followed by `listen("run-event", handler);` at top level of a `.weiv` component script. Build with `npm run build`, then run the bundle or evaluate it in a DOM environment.
- **Expected:** imported binding is initialized before the call.
- **Actual:** mount throws `ReferenceError: Cannot access 'listen' before initialization` (minified name `H` in the release bundle), leaving the Tauri window blank. The generated component initialization calls the listener before its tracked import binding is initialized.
- **Workaround:** defer registration with `queueMicrotask(() => listen("run-event", handler))`. The rendered DOM then mounts successfully.
- **Verification:** the release JavaScript was evaluated in jsdom before and after the change; before it threw that error, afterward it rendered the sidebar and welcome text.

### Published Vite plugin omits component styles

- **Category:** packaging/tooling defect in published `weivjs` 0.1.1.
- **Context:** Atelier imports `App.weiv` through `weivjs/vite` with Vite 7.3.7 and packages the result in Tauri 2 on macOS.
- **Reproduce:** create a `.weiv` component with a `<style>` block, import it from a Vite entry, and run `vite build` using the published `weivjs/vite` plugin.
- **Expected:** a CSS asset is emitted and referenced by the built HTML.
- **Actual:** Vite emits only JavaScript; the app renders as unstyled HTML. The installed `node_modules/weivjs/dist/vite.mjs` compiles only `js`, while the newer local Weiv source includes a CSS virtual module path.
- **Workaround:** `vite.config.ts` adds a small virtual CSS loader that invokes `weiv compile emit css` for `App.weiv`, and `src/main.ts` imports that virtual style module. Vite now emits a CSS asset referenced by `dist/index.html`.

### Some event expressions run outside Weiv's update boundary

- **Category:** compiler/runtime integration defect.
- **Context:** Weiv 0.1.1 component with a button using `@click="selectEngine('codex')"`.
- **Reproduce:** in a component, update a template-bound `let selectedEngine` inside `selectEngine`; bind the button using a call expression and click it.
- **Expected:** the selected button and related text update immediately.
- **Actual:** localStorage changed, but template content did not update. Generated code evaluated `instance.refresh().selectEngine("codex")` before checking whether the result was a function to run in Weiv's update boundary.
- **Workaround:** bind a named function, `@click="selectCodex"`, whose body calls `selectEngine("codex")`. The named handler runs inside the update boundary.

### Compound expressions lose component or loop scope

- **Category:** compiler defect in generated JavaScript.
- **Context:** Weiv 0.1.1 template with a conditional conversation view and a `#for` message loop.
- **Reproduce:** bind a placeholder with `:placeholder="'Ask ' + engineName()"`, or render `{{ message.role === 'user' ? 'You' : engineName() }}` inside `#for="message in messages"`.
- **Expected:** both the component function and loop variable resolve correctly.
- **Actual:** the first expression emitted an unscoped `engineName()` and threw `ReferenceError: engineName is not defined` when the conversation view appeared. The second emitted unscoped `message.role` and threw `ReferenceError: message is not defined` when messages rendered.
- **Workaround:** use a static placeholder and keep the loop label expression independent of the component function. The built-app smoke test now covers both transitions.

### `weivUpdate` is unavailable in a deferred external callback

- **Category:** compiler/runtime integration defect.
- **Context:** Tauri event subscription registered in a microtask to avoid the import initialization bug above.
- **Reproduce:** call `weivUpdate(() => { ... })` in the Tauri event callback and deliver a `run-event` message.
- **Expected:** local state changes flush to the component, as described in Weiv's external callback documentation.
- **Actual:** generated code retains `weivUpdate(...)` as an unresolved global and throws `ReferenceError: weivUpdate is not defined`.
- **Workaround:** the external callback stores the event, then clicks a hidden component button bound to the named `applyRunEvent` handler. The state change runs in Weiv's own event boundary. The smoke test delivers session, answer, and done events through this path.

### Window keyboard listeners do not flush component state

- **Category:** runtime integration defect; same external update boundary issue as Tauri event callbacks.
- **Context:** Atelier with Weiv 0.1.1, Vite 7.3.7, Node 22.22.1, Tauri 2; reproduced in the built UI smoke test with jsdom 29.1.1.
- **Reproduce:** register `window.addEventListener("keydown", handler)` from a `.weiv` script via `queueMicrotask`. In the handler, call a component function that updates template-bound state, such as `openFilesPanel()` assigning `panelMode = "files"`. Dispatch Cmd+P.
- **Expected:** the Files panel appears, as it does when its visible Weiv button is clicked.
- **Actual:** the listener runs but the panel is absent because its state changes occur outside Weiv's update boundary. The smoke test failed with `AssertionError: file search shortcut must open Files` and `document.querySelector(".inspector") === null`.
- **Workaround:** the keyboard listener programmatically clicks hidden buttons bound to named Weiv handlers. The same smoke test then passes and the panel appears.

### Scoped style compiler produces invalid global selectors

- **Category:** confirmed compiler/tooling defect in Weiv 0.1.1; workaround available.
- **Context:** Atelier's separate Weiv remote page (`src/Remote.weiv`) with Vite 7.3.7, Node 22.22.1, macOS, and the `weiv compile emit css` workaround for the published Vite plugin.
- **Reproduce:** put `* { box-sizing: border-box; } body { margin: 0; } button { cursor: pointer; }` in a `.weiv` `<style>` block, import its emitted CSS, then run `npm run build:remote`.
- **Expected:** valid scoped CSS or a clear unsupported-global-selector diagnostic.
- **Actual:** esbuild warns `Unexpected "*" [css-syntax-error]` for a selector shaped `[data-weiv-scope="..."]*`, and similarly warns for `body` and `button`; those rules are not applied.
- **Workaround:** anchor the rules under the component root (`.remote-shell *`, `.remote-shell button`) and place document-wide styles outside the scoped component if needed. The remote build then has no CSS warnings.

### Conditional sibling after a looped message body loses loop scope

- **Category:** confirmed generated JavaScript defect in Weiv 0.1.1.
- **Context:** Atelier chat timeline in `src/App.weiv`, Vite 7.3.7, Node 22.22.1, jsdom 29.1.1, macOS. The local Weiv source checkout was at commit `1633af0` during this work; the app uses the published 0.1.1 package.
- **Reproduce:** inside `<article #for="message in messages">`, render a `<div #if="message.role !== 'tool'">` and a following sibling `<details #if="message.role === 'tool'">` with `{{ message.text }}`. Build with `npm run test:ui`, then deliver a chat run event in the smoke test.
- **Expected:** the sibling conditional and interpolation resolve the current `message` loop item.
- **Actual:** the build succeeds, but rendering logs the following error repeatedly and the smoke test fails at `AssertionError: question card must appear` because rendering stops. Removing those sibling conditionals makes the same test pass.

  ```text
  ReferenceError: message is not defined
      at ag (evalmachine.<anonymous>:24:26474)
      at x_ (evalmachine.<anonymous>:17:59015)
      at og (evalmachine.<anonymous>:24:26429)
      at h (evalmachine.<anonymous>:17:52002)
      at l_ (evalmachine.<anonymous>:17:53460)
      at c_ (evalmachine.<anonymous>:17:53720)
      at $m (evalmachine.<anonymous>:24:24220)
      at n_ (evalmachine.<anonymous>:17:49757)
      at na (evalmachine.<anonymous>:24:23669)
      at w1 (evalmachine.<anonymous>:25:15669)
  AssertionError [ERR_ASSERTION]: question card must appear
      at file:///Users/chao.yang/Private/atelier/test/smoke.mjs:128:1
  ```
- **Workaround:** render the standard body and a `<details>` body unconditionally inside the loop, then use the article role class to show the appropriate one with CSS. A compiler fix should preserve loop scope for sibling `#if` nodes.

## CC GUI desktop migration follow-up (2026-10-27)

Context: adding a Weiv chat entry alongside the existing React entry in CC GUI. Environment: macOS arm64, Node 22.22.1, pnpm 10.29.3, Vite 6.4.3, `weivjs` 0.1.1.

## Confirmed compiler defect: imported function used before initialization

Reproduction: create a `.weiv` component with `<script lang="ts">import { snapshot } from "./adapter"; let initial = snapshot();</script>`, compile it with `weiv compile emit js`, and mount it. Expected: `snapshot()` runs during setup. Actual: the generated `setup()` calls `snapshot()` before its later `const snapshot = __weiv_getTrackedRoot(...)` declaration. Chrome reports `ReferenceError: Cannot access 'snapshot' before initialization`, leaving only root comment nodes in the page. Workaround in `src/weiv/App.weiv`: initialize local values without the import, then read the store in a queued microtask after setup completes. The fallback text in `src/weiv/main.ts` also prevents a silent blank page if mounting throws again.

## Tooling gap: component styles are omitted by the Vite plugin

Reproduction: add `<style>.example { color: red }</style>` to a `.weiv` component, import the component through `weivjs/vite`, and build with Vite. Expected: the component's CSS appears in the page. Actual: the emitted JavaScript includes the component, but the CSS is absent. Current workaround: keep shared styles in `src/weiv/app.css` and import that file from `src/weiv/main.ts`. An earlier workaround called `weiv compile emit css` through a local Vite plugin, but splitting the UI made a normal stylesheet simpler.

## Tooling gap: sibling component imports do not resolve in Vite

Reproduction: create `Parent.weiv` with `import * as Child from "./Child.weiv"` and `<Child />`, then run Vite build with `weivjs/vite`. Expected: Vite bundles both components. Actual: Weiv emits `import * as Child from "./Child.mjs"`, and Vite reports `Could not resolve "./Child.mjs" from "Parent.weiv"`. Workaround: the small `ccgui-weiv-component-imports` Vite resolver maps an emitted local `.mjs` import back to an existing `.weiv` source.

## Compiler defect: object shorthand in component props emits invalid JavaScript

Reproduction: pass `:view="{ open, page }"` to a child component and run `weiv compile emit js Parent.weiv`. Expected: generated JS uses `open: scope.open, page: scope.page`. Actual: it emits `{ scope.open, scope.page }`, which Rollup rejects with `Unexpected token '.'`. Workaround: spell every object key explicitly, such as `:view="{ open: open, page: page }"`.

## Compiler defect: child component in a conditional branch can update before mount

Reproduction: put `<Child :view="{ value: value }" />` inside a `#if="selected"` section, change `selected` from false to true, and update the parent. Expected: Child mounts and receives props. Actual: the generated `updateRegion_child` calls `refs[index].setProps(...)` while that ref is undefined, throwing `Cannot read properties of undefined (reading 'setProps')`. Workaround: keep the chat section mounted and bind its native `hidden` attribute; CSS hides `[hidden]` without tearing down the child component.

## Compiler defect: complex prop member expression can remain unscoped

Reproduction: in a child component, use `:disabled="(!props.view.draft.trim() && !props.view.attachments.length) || !props.view.hasActiveChat"`. Expected: generated render code resolves `props` through `scope`. Actual: it emits bare `props.view...` in the initial render and throws `ReferenceError: props is not defined`. Workaround: derive `sendDisabled` in the parent and bind the child attribute to `props.view.sendDisabled`.

The same unscoped expression occurred in a Settings `#if` combining `!props.view.settingsQuery` with `String.includes(props.view.settingsQuery)`. Deriving simple `showGeneral` / `showClaude` / `showCodex` booleans in the parent avoided the crash.

## Diagnostics gap: HTML void tags reported as mismatched close at template start

Reproduction: add `<label>Name<input name="name"></label>` to a Weiv template and run `weiv compile emit js`. Expected: the parser accepts the HTML void tag or points at the input that needs closing. Actual: compilation stops with `error template.mismatched_close_tag [template_parse] [1:11] [10..11] fatal: Closing tag does not match the currently open element`, which points at the beginning of `<template>` rather than the offending input. Workaround: write `<input name="name" />` explicitly. This is a diagnostics and HTML compatibility gap, not a confirmed runtime defect.

## Confirmed reactivity gap: assignments after await do not repaint

Reproduction: in a `.weiv` event handler, call an async function that sets `busy = true`, awaits an IPC promise, then sets `busy = false` and replaces a list used by `#for`. Expected: the busy state clears and the list repaints when the promise settles. Actual: the busy indicator stays visible and the list keeps its old rows even though the backend mutation and reload finish. A no-op DOM event dispatched afterward also fails because Weiv takes its before-snapshot after the lexical assignments have already occurred. Workaround: keep the `mount()` handle and call its public `update()` method after async assignments (`src/weiv/ui-refresh.ts`). Verified with a mocked Tauri IPC flow that saved a provider profile and then displayed its row.

## Loop identity can recreate a streaming message row

In the emitted `#for` code for `message in messages`, the key is `item?.id ?? item`. Chat messages have `seq` but no `id`; an immutable update to a live message therefore changes the object key and replaces that row's DOM. This can reset selection or an expanded tool output while text streams. Workaround in `src/weiv/chat-adapter.ts`: project each message to a stable `id` based on session key and sequence, caching unchanged source messages in a `WeakMap`. This is an integration constraint of the default loop key, not a confirmed compiler defect.

These reports are local engineering notes; no external issue was submitted.

## Packaged app CSP incompatibility: component prop objects use runtime evaluation

Context: packaging the Weiv 0.1.1 entry in Tauri 2.11.5 on macOS arm64 with the project's production CSP (`script-src 'self' blob: pluginasset: http://pluginasset.localhost`). Reproduction: build `weiv.html` with Vite, package it as the Tauri window URL, then launch the `.app`. Expected: the compiled component props mount under the existing CSP. Actual: the window displays `EvalError: Refused to evaluate a string as JavaScript because 'unsafe-eval' or 'trusted-types-eval' is not an allowed source of script`. `weiv compile emit js src/weiv/App.weiv` showed that inline object-valued component props called `__weiv_evaluate`, which uses the `Function` constructor; the production asset contained the same fallback. Workaround verified: move each object expression into a named component function and bind `:view="timelineView()"` rather than an inline object. The generated Weiv entry asset then contained no `Function(...)` call or runtime fallback warning. The unsigned macOS preview launched under the normal CSP and restored a transcript, opened Settings, and searched the transcript in WKWebView. This is a Weiv compiler/runtime capability gap in published 0.1.1; the local Weiv checkout reports a fix in current source.

## Project-specific Tauri preview window conflict

Context: the same isolated native preview. Reproduction: override `app.windows` with a `main` window in `tauri.weiv.bundle.conf.json` while `src-tauri/src/lib.rs` also creates `main` during setup, then package and launch. Expected: one Weiv window. Actual: startup aborts with `failed to create main window: WebviewLabelAlreadyExists("main")`. Workaround: keep `app.windows` empty and choose `weiv.html` in the existing window builder when the preview bundle identifier is active. This is a project integration issue rather than a Weiv defect.

## Template compatibility gap: HTML entity is shown literally

Context: the Weiv 0.1.1 settings rail on macOS arm64, Node 22.22.1, pnpm 10.29.3, Vite 6.4.3. Reproduction: put `<div>WORKSPACE &amp; DATA</div>` in a `.weiv` template, build with `corepack pnpm build`, and mount it in Chrome via Vite. Expected: the accessible text and rendered heading say `WORKSPACE & DATA`. Actual: the browser accessibility tree says `WORKSPACE &amp; DATA`. Workaround tried and retained: use `WORKSPACE AND DATA` in the template. This is an HTML entity compatibility gap, not a settings data defect.

## Compiler defect: local const is reassigned during setup

Context: adding collapsible workspace groups to `App.weiv`, same Weiv 0.1.1 macOS/Node/pnpm/Vite environment above. Reproduction: declare `const collapsedGroups = new Set<string>();` in a component script and read it from a function used by the template. Build succeeds, but mounting the component throws `TypeError: Assignment to constant variable.` The emitted `setup()` contains `collapsedGroups = __weiv_getTrackedRoot("collapsedGroups", collapsedGroups);` after the original `const` declaration. Expected: the compiler preserves `const` or uses a separate binding. Actual: it writes to the constant. Workaround: declare the set with `let`; a browser fixture then mounts. This is a confirmed compiler defect.

## Compiler defect: type-only named import becomes a runtime reference

Context: adding `SessionSearch.weiv` to the Weiv 0.1.1 entry. In `App.weiv`, add `import { ipc, type MessageSearchHit } from "@/lib/ipc";` and use `MessageSearchHit[]` only as a TypeScript annotation. Build with `corepack pnpm build` and open `weiv.html`. Expected: the type import is erased and the app mounts. Actual: the build succeeds, but mounting throws `ReferenceError: __weiv_import_MessageSearchHit is not defined`, shown by the app's error fallback. Workaround: import only the runtime `ipc` value and use a local structural type for the search hits. This was verified by rerunning the mocked Tauri UI smoke: mount, chat send, provider save, theme switch, and search IPC call then worked without runtime exceptions.

The same defect recurred in `Sidebar.weiv` during worktree progress migration with a pure `import type { PendingCreation } from "@/features/worktree/store";` and `PendingCreation[]` as a function return type. `corepack pnpm build` and a Tauri debug bundle both succeeded, but the native WKWebView error fallback showed `ReferenceError: Can't find variable: __weiv_import_PendingCreation`. Replacing the import with a local structural `type PendingCreation = { ... }` is the workaround. This confirms the problem also affects standalone `import type`, not only inline `type` specifiers.

Source follow-up (2026-10-28): in the current checkout, the parser already marks these bindings `type_only`, and `buildPreservedImports` erases them. `buildSetupCode` omitted that filter in its initialization, scope, and observable subscription loops, leaving references to imports that do not exist at runtime. A regression test now covers both `import type { Standalone }` and `import { format, type Inline }`; the three setup loops use the same runtime-import filter as preserved imports. Verified with Zig 0.16 `zig build test` on macOS arm64. The installed Zig 0.17 cannot run this repository's build script (`no field named 'args' in struct 'Build'`).

## Investigation: nested worktree progress loop coincides with duplicate sidebar rows

Context: CC GUI's `Sidebar.weiv` on Weiv 0.1.1, Node 22.22.1, pnpm 10.29.3, Vite 6.4.3, Tauri 2.11.5, macOS arm64. Add a pending worktree `#for` inside an existing nested `#for` over workspace sections/workspaces, with `#if="workspace.children.length || pendingFor(workspace.id).length"`, where `pendingFor` filters a prop array. Build and launch the native preview, then open a workspace action menu and select New Worktree. Expected: one workspace row and a creation dialog. Actual observed: every UI refresh appended another visible copy of the workspace row and its session row; the dialog did not appear. The browser fixture exposed the cause: `ReferenceError: workspace is not defined` at `updateConditional_55`, and emitted JS contains `Boolean(workspace.children.length || scope.pendingFor(workspace.id).length)` inside a scope where only `scope.workspace` exists. Classification: **confirmed compiler scoping defect** for a nested-loop condition calling a function with the loop item. Workaround: project `pending` onto each workspace node in TypeScript, then use `#if="workspace.children.length || workspace.pending.length"` and `#for="pending in workspace.pending"`. After that change, the browser fixture renders one workspace row and opens the creation dialog. Native retest is pending. No external issue submitted.

The same unscoped expression defect occurred in `WorktreeDelete.weiv` with `{{ props.view.locked || props.actions.text('worktree.lockedDeleteDisabled') }}`. `weiv compile emit js` produced `String((props.view.locked || props.actions.text(...)) ?? "")` instead of `scope.props`, and native WKWebView showed `ReferenceError: Can't find variable: props` on opening the delete dialog. Workaround: compute `lockedLabel` in its TypeScript controller and bind `{{ props.view.lockedLabel }}`. The regenerated JS has no bare `props` expression at that text binding. The native preview then showed the Git lock reason and kept Delete disabled; after unlocking the disposable worktree, deletion succeeded.

The existing-branch tab in `WorktreeCreate.weiv` hit a similar failure with `{{ props.view.occupied.includes(branch.name) ? ' · checked out' : '' }}` inside an `<option #for="branch in ...">`. The browser fixture reported `ReferenceError: props is not defined` at `updateRegion_text_45`; the emitted JS used bare `props.view.occupied` and `branch.name`. The native selector consequently showed a branch but did not advance the form. Workaround: project `{ name, label, occupied }` branch options in the TypeScript controller and bind the simple `branch.label` and `branch.occupied` properties. The fixture then displayed the suggested location and enabled Create after choosing the existing branch; the native preview also created a worktree from that retained branch. A follow-up UI issue showed the selector visually reverting to its placeholder even though the controller kept the selected branch. Explicit `:selected` bindings on projected option properties fixed that display in the browser fixture and in the packaged macOS WKWebView preview: selecting `feature/select-smoke` kept the branch name visible and filled the corresponding location. The test dialog was canceled and the disposable branch removed.

### Diagnostics gap: malformed TypeScript silently discards the component script

- **Classification:** confirmed compiler diagnostics defect in published `weivjs@0.1.1`; current source was not yet retested.
- **Context:** `Sidebar.weiv` in the CC GUI Tauri migration, macOS arm64, Node 22.22.1, pnpm 10.29.3, Vite 6.4.3.
- **Minimal reproduction:** create `<template><button @click="click">Go</button></template><script lang="ts">let id = "a"; let rows: any[] = []; function click() { rows.some((row: any) => row.id === id; }</script>` (the call deliberately lacks a closing `)`). Run `weiv compile emit js component.weiv`.
- **Expected:** a syntax diagnostic and nonzero exit, pointing to the unmatched parenthesis.
- **Actual:** exit status 0 with no diagnostic output. The emitted `setup()` contains only the generated `props` binding; `click` and all other component script declarations are omitted. The page mounts but its buttons silently do nothing. In the CC GUI case, the malformed expression had 8 opening and 7 closing parentheses; `corepack pnpm build` succeeded and the browser fixture showed no action after clicking.
- **Workaround:** simplify the expression, fix the syntax, and inspect generated JavaScript for expected functions. The corrected `Sidebar.weiv` emitted `function showWorkspaceMenu` and the browser action worked.

## Integration gap: boolean data binding does not round-trip as string "true"

- **Classification:** template/DOM interoperability gap in published `weivjs@0.1.1`; no compiler defect established.
- **Context:** CC GUI React-to-Weiv file tree, macOS arm64, Node 22.22.1, pnpm 10.29.3, Vite 6.4.3. The row click handler distinguishes folders from files using a `data-*` value.
- **Reproduce:** render `<button :data-dir="row.isDir" @click="openRow">Open</button>` inside `#for="row in props.view.rows"`, with `row.isDir === true`. In `openRow`, read `(event.currentTarget as HTMLElement).dataset.dir === "true"` and click the folder in the browser fixture `tests/browser/weiv-timeline-search.html`.
- **Expected:** the dataset comparison is true and the folder expands, or the binding documentation makes the boolean-to-attribute conversion explicit.
- **Actual:** the comparison is false; clicking `src` calls the file-open path and creates a `src` editor tab. The generated attribute is not a dependable string `"true"` for this handler.
- **Workaround:** project `kind: row.isDir ? "dir" : "file"` in `src/weiv/file-tree-view.ts`, bind `:data-kind="row.kind"`, and compare with `"dir"`. The browser fixture then expanded `src` and displayed its `main.ts` child. No private workspace content is needed for reproduction.
The type-only import defect recurred during Git-list virtualization (macOS arm64, Node 22.22.1, pnpm 10.29.3, Vite 6.4.3, `weivjs@0.1.1`, Weiv checkout `1633af0`). In `src/weiv/App.weiv`, `import { projectGitChanges, type GitListMode } from "./git-changes-view"; let gitViewMode = "tree" as GitListMode;` passed `corepack pnpm build`, but the Chrome fixture `tests/browser/weiv-timeline-search.html?manyChanges=1` failed at mount with `ReferenceError: __weiv_import_GitListMode is not defined` in generated `setup()`. Expected: the type-only binding is erased. Removing the imported type and its assertion restored mounting. This is the same confirmed compiler defect described above.


## Packaged diff rows overlapped with per-row absolute positioning

- **Classification:** Weiv/Tauri production rendering interoperability gap; the exact compiler or WKWebView cause is not established, so this is not a confirmed Weiv defect.
- **Context:** CC GUI Weiv Git diff migration, `weivjs@0.1.1` (local Weiv checkout `1633af0`), macOS arm64 WKWebView in Tauri, Node 22.22.1, pnpm 10.29.3, Vite 6.4.3. Chrome Vite fixture rendered the same diff correctly.
- **Reproduce:** in `GitDiff.weiv`, render projected diff rows with `#for="line in props.view.lines"`, bind each row's `:style="line.style"` where `line.style` is `top:0px`, `top:20px`, etc., and set `.git-diff-line { position:absolute; height:20px }`. Build with `corepack pnpm exec tauri build --debug --bundles app --config src-tauri/tauri.weiv.bundle.conf.json --no-sign`, launch the preview, and open an untracked two-line text file from Changes. A Chrome fixture at `tests/browser/weiv-timeline-search.html` is the comparison.
- **Expected:** each diff row appears at its projected vertical offset in both Chrome and packaged WKWebView.
- **Actual:** Chrome showed separate lines; the packaged app painted all diff text on top of itself at the first row. No JavaScript error was observed. The first native screenshot was taken after the diff loaded, and the app's Git status and target file were correct.
- **Workaround:** remove per-row absolute positioning and render the bounded row window in normal flow, with a single projected `padding-top` offset on its wrapper and a total-height sizer. Rebuilding the app displayed the header, hunk, two green additions, and line numbers on separate rows. This is a confirmed project integration workaround; root cause remains open.

The same imported-binding initialization defect recurred while adding the Weiv terminal dock. `App.weiv` declared `let terminalOpen = useTerminalStore.getState().open;` at component setup, with `useTerminalStore` imported from `@/features/terminal/store`. `corepack pnpm build` succeeded, but the Chrome fixture failed to mount with `ReferenceError: Cannot access 'useTerminalStore' before initialization` at generated `setup()` line 1391. Expected: the imported store is initialized before the setup expression. Moving the store read and `WeivTerminalController` construction into the existing `queueMicrotask` initialization restored mounting; the packaged macOS preview then opened a PTY and displayed shell output. Environment: `weivjs@0.1.1`, local Weiv checkout `1633af0`, macOS arm64, Node 22.22.1, pnpm 10.29.3, Vite 6.4.3. This is a recurrence of the confirmed compiler defect above, not a new issue.

## Packaged terminal context menu ignored bound position

- **Classification:** production Weiv/WKWebView style-binding interoperability gap; root cause unconfirmed.
- **Context:** CC GUI Weiv terminal dock, `weivjs@0.1.1` (local checkout `1633af0`), macOS arm64, Tauri packaged WKWebView, Node 22.22.1, pnpm 10.29.3, Vite 6.4.3.
- **Reproduce:** select text in the xterm dock, right-click near the middle of the dock, render `<div class="weiv-terminal-menu" :style="props.view.menu.style">` with `position:fixed` CSS and a projected `left:${x}px;top:${y}px` string from the pointer event. Build with `corepack pnpm exec tauri build --debug --bundles app --config src-tauri/tauri.weiv.bundle.conf.json --no-sign` and launch the preview.
- **Expected:** the menu appears by the pointer, clamped to the viewport.
- **Actual:** the packaged menu appeared at the terminal dock's left edge regardless of the projected position. No runtime error appeared; right-click selection and menu entries worked. The screenshot showed the click around x=700 and menu starting at the main pane's x=520. A browser comparison was not performed for this exact binding.
- **Workaround:** after Weiv renders the menu, set the menu element's `style.left` and `style.top` directly from the saved pointer coordinates, including after view refreshes. The next native build placed the menu beside the pointer. A final packaged build verified that focusing the menu allows Escape to close it.

## SVG template nodes use the HTML namespace (2026-10-28)

- **Classification:** confirmed `weivjs@0.1.2` compiler/runtime defect affecting inline SVG; no exception is raised.
- **Context:** CC GUI fresh `IconButton.weiv` and `CloseButton.weiv` mechanical port, macOS arm64, Node 22.22.1, Vite 6.4.3, Chromium in Codex in-app browser, Weiv checkout `355153dae17b345094bbe6ba269dc8b01a43cddb`.
- **Reproduction:** compile and mount `<template><button><svg width="10" height="10" viewBox="0 0 10 10"><path d="M0 0L10 10" /></svg></button></template>` with `weivjs@0.1.2`; inspect `button.querySelector('svg').namespaceURI` and its bounding box. The CC GUI fixture is `src/weiv-fresh/CloseButton.weiv` before its SVG was moved to the adapter.
- **Expected:** SVG and path use `http://www.w3.org/2000/svg`, and the SVG occupies the declared 10×10 box, as in the React reference.
- **Actual:** SVG and path use `http://www.w3.org/1999/xhtml`; the `viewBox` attribute is serialized as lowercase `viewbox`, and the SVG box is 0×0. The close-button row shifts vertically because its glyph contributes no height. No console error or build error appears.
- **Workaround:** keep button structure/classes in `.weiv`, then insert fixed, locally generated SVG markup into the mounted button or slot from the preview adapter. HTML parsing creates SVG namespace nodes. With this adapter, all four icon-button and four close-button fixtures match React box geometry and computed style in both themes. This is a preview workaround; lifecycle integration for production components remains open.
- **Related finding:** binding `:innerHTML` in a `.weiv` template writes a literal lowercase `innerhtml` attribute instead of assigning the DOM property, so it does not provide an in-component workaround.

## Global `Math` unavailable in template expressions (2026-10-28)

- **Classification:** confirmed published `weivjs@0.1.2` template evaluation defect; local source checkout at `355153dae17b345094bbe6ba269dc8b01a43cddb` was not retested.
- **Context:** CC GUI `ImageLightbox.weiv` zoom label, macOS arm64, Node 22.22.1, Vite 6.4.3, Chromium in Codex in-app browser. The production build completed successfully.
- **Reproduction:** mount a component with `let zoom = 1` and template text `{{ Math.round(zoom * 100) }}%`; click a handler that changes `zoom` to 1.25.
- **Expected:** initial text `100%`, then `125%`.
- **Actual:** browser text was only `%` in both states. Console reported `TypeError: Cannot read properties of undefined (reading 'round')` from generated Weiv code on mount and update. The full error began `at wf (.../assets/weiv-DZGn53IU.js:1:249017)`; browser URL was `http://localhost:1421/weiv.html?lightbox=1`.
- **Workaround:** track a script-local `zoomLabel` string, update it with `Math.round` in the component handler, and bind `{{ zoomLabel }}`. A rebuilt 0.1.2 browser fixture showed 100% → 125% → 100% with no new errors from that build.

## Proxied arrays break native `Array.map` in 0.1.2 (2026-10-28)

- **Classification:** confirmed runtime defect in published `weivjs@0.1.2`; distinct from the earlier 0.1.1 `filter` report because this reproduction uses 0.1.2 and `map`.
- **Context:** CC GUI fresh `TerminalDock.weiv` preview, macOS arm64, Node 22.22.1, Vite 6.4.3, Chromium in Codex in-app browser, Weiv source reference `355153dae17b345094bbe6ba269dc8b01a43cddb`.
- **Reproduction:** mount a component with array props `tabs` and top-level script `let localTabs = props.tabs.map((tab, index) => ({ ...tab, id: index }))`. The CC GUI fixture was `http://localhost:1421/weiv.html` with a separately built 0.1.2 production bundle.
- **Expected:** the terminal dock and subsequent app shell mount with cloned tab items.
- **Actual:** mount throws `TypeError: 'get' on proxy: property 'prototype' is a read-only and non-configurable data property on the proxy target but the proxy did not return its actual value (expected '[object Array]' but got '[object Object]')` at `Proxy.map`; the terminal dock and subsequent fixture content do not mount. TypeScript and Vite build both pass.
- **Workaround:** iterate with `for…of` into a fresh plain array. The same approach replaces `map`, `filter`, and `some` on tracked local tab arrays in the component until their runtime behavior is verified.

### Additional `filter` reproduction in Affon report (2026-10-29)

- **Classification:** same proxy/native-array runtime defect, reproduced with current local Weiv checkout `05c502437085032010cd46b3ad3012f98c3f7990`; no new defect category.
- **Context:** Affon performance report at `benchmarks/report/App.weiv`, macOS arm64, Node 22.22.1, Bun 1.2.16, `weiv compile` from local checkout followed by `bun build --target browser --format iife`. The generated self-contained HTML was loaded under `file://` and checked with jsdom 29.1.1.
- **Reproduction:** define `export let props` with `cases: { id: string }[]`, call `props.cases.filter(item => item.id.includes(query))` from a template expression such as `{{ visibleCases().length }}`, compile and mount with a nonempty `cases` array.
- **Expected:** initial render shows the count and rows; changing the query filters them.
- **Actual:** mount throws `TypeError: 'get' on proxy: property 'prototype' is a read-only and non-configurable data property on the proxy target but the proxy did not return its actual value (expected '[object Array]' but got '[object Array]')` at `Proxy.filter`. The table stays empty. The same exception recurs on input. The complete stack begins at `Proxy.filter`, `Object.visibleCases`, `updateRegion_text_45`, `updateDom`, `instance.update`, `mountIntoBoundary`, and `mount` in the emitted bundle.
- **Workaround:** iterate by numeric index over `props.cases` and push matching items into a fresh array. The saved report then mounts ten rows, filters to one row by search, and filters to three candidate gaps by status without an error.
## Bundling a Weiv page in a macOS WKWebView (2026-10-29)

- **Classification:** documentation gap and integration limitation; no confirmed compiler defect.
- **Context:** Cyna app framework proof, macOS arm64, Node 22.22.1, Cyna 0.4.0, local Weiv commit `05c502437085032010cd46b3ad3012f98c3f7990`, `WKWebView` loading bundled assets.
- **Reproduction:** create `App.weiv` with `<script>let count = 0;</script>`, then run `node packages/weiv/bin/weiv.mjs compile emit app App.weiv dist`. After changing it to `<script lang="ts">`, load `dist/index.html` with `WKWebView.loadFileURL` and allow read access to `dist`.
- **Expected:** the documented plain `<script>` example compiles, and the emitted standalone app loads from a bundled file URL or documents that it requires an HTTP/custom-scheme origin.
- **Actual:** compilation first reports `weiv validate app failed for web/App.weiv` and `error sfc.invalid_script_attributes [sfc_parse] fatal: Only <script lang="ts"> is supported`. With `lang="ts"`, the generated `index.html` points at `/styles.css` and `/main.mjs`; the file-backed WKWebView displays a blank page because those root-relative assets do not resolve in the bundle.
- **Workaround:** use `<script lang="ts">` and serve the output through a registered `cyna-app://` WKURLSchemeHandler. The same compiled bundle then renders and handles Cyna command replies. A relative-asset emit option or explicit packaging guidance would simplify this use case.

## Inline range value expression in Cyna playback proof (2026-10-29)

- **Classification:** Weiv template binding or WKWebView interoperability gap; cause not yet isolated.
- **Context:** Cyna app framework playback proof, macOS arm64 WKWebView, Node 22.22.1, local Weiv commit `05c502437085032010cd46b3ad3012f98c3f7990`.
- **Reproduction:** in a `.weiv` component, initialize `let position = 0`, render `<input type="range" min="0" max="1000" :value="Math.round(position * 100)" />`, compile with `node ../weiv/packages/weiv/bin/weiv.mjs compile emit app web/App.weiv web/dist`, package the emitted page under `cyna-app://`, and inspect the slider at mount.
- **Expected:** the range value starts at 0, matching `position` and the adjacent `{{ position.toFixed(2) }}` text.
- **Actual:** the adjacent text showed `0.00`, while the range control started at its browser default midpoint, value 500. Compilation reported no error. No console error was captured.
- **Workaround:** define `function timelineValue() { return Math.round(position * 100); }` in the component script and bind `:value="timelineValue()"`. The rebuilt packaged WKWebView then showed slider value 0 at mount and updated it after a seek.

## Bare element selectors in packaged Ceiv Lightcept UI (2026-11-01)

- **Classification:** Weiv scoped-CSS/runtime integration defect candidate; packaged rendering reproduced, root cause not isolated.
- **Context:** Lightcept Ceiv first native-preview shell, macOS arm64 WKWebView under `cyna-app://local`, Node 22.22.1, Cyna 0.4.1, Ceiv 0.1.0, `weivjs` 0.1.2, local Weiv source commit `05c5024`. Source: `src/ui/ceiv/web/App.weiv` in Lightcept. No customer data is needed.
- **Reproduction:** build the Ceiv app with `src/ui/ceiv/build.sh`; open the packaged app. In a `.weiv` style block, use `body { font: 14px -apple-system, sans-serif; }`, `header { height: 52px; display: flex; }`, and `header strong { font-size: 18px; }`. Inspect the header after the page loads. The compiled CSS includes selectors such as `header[data-weiv-scope="..."]` and `[data-weiv-scope="..."] header`.
- **Expected:** the brand uses the declared system font and 18px size in a 52px flex header.
- **Actual:** the packaged WKWebView showed default serif text and a taller header; the brand and adjacent status did not receive the intended styling. The native preview still rendered. The build completed without CSS errors.
- **Workaround:** assign explicit classes to the component elements and style `.app`, `.topbar`, `.brand`, and `.status`. `body` is outside the component scope and cannot be styled with the scoped `body` rule. The class-based replacement was rebuilt and visually verified in the same packaged WKWebView: the header uses the system font, intended size and spacing.

## Unknown `v-if` attribute silently leaves conditional controls visible (2026-11-01)

- **Classification:** confusing directive API and missing diagnostic; the supported Weiv directive is `#if`, so this is not evidence that `#if` itself is defective.
- **Context:** Lightcept Ceiv `src/ui/ceiv/web/App.weiv`, macOS arm64 WKWebView under `cyna-app://local`, Node 22.22.1, Ceiv 0.1.0, `weivjs` 0.1.2, local Weiv source commit `05c502437085032010cd46b3ad3012f98c3f7990`.
- **Reproduction:** in a `.weiv` component, set `let opening = false` and render `<button v-if="opening">Cancel Open</button>`. Build with `src/ui/ceiv/build.sh` and launch the packaged app. An existing `<div v-if="!hasPhoto">` showed the same missing conditional behavior after a photograph opened.
- **Expected:** either the control follows the condition, or compilation diagnoses `v-if` as an unsupported directive and points to `#if`.
- **Actual:** build completed without a diagnostic, and the packaged page visibly showed Cancel Open while `opening` was false. There was no compiler error output. The unsupported attribute was treated as an ordinary HTML attribute.
- **Workaround:** replace `v-if` with `#if`, as shown in Weiv's `test/examples/basic/conditional-toggle.weiv`, then rebuild. The resulting template uses Weiv's structural condition. No private photograph or customer data is needed to reproduce this report.

## Boolean `aria-selected` binding reports the active tab as off (2026-11-05)

- **Classification:** confirmed accessibility binding behavior in the packaged Weiv page; whether this is compiler coercion or WKWebView attribute handling is not yet isolated.
- **Context:** Lightcept Ceiv `src/ui/ceiv/web/App.weiv`, macOS arm64 WKWebView under `cyna-app://local`, Node 22.22.1, Ceiv 0.1.3, Weiv 0.1.2 at local source commit `bc512d9`. The native Ceiv build completed successfully and reported no Weiv error.
- **Reproduction:** render a tablist with `let activeTab = 'light'` and `<button role="tab" :aria-selected="activeTab === 'light'">Light</button>`. Build the bundled app with `src/ui/ceiv/build.sh`, launch it, and inspect the active tab through macOS accessibility. Change `activeTab` to another tab and inspect again.
- **Expected:** the active tab is reported as selected, and the other tabs as selectable.
- **Actual:** the active tab was reported as `tab (selectable) Light` at mount. After selecting Color, accessibility reported `tab (selectable) Color, Value: off`; the visual selected style and panel content did update. No compiler or runtime error was reported.
- **Workaround:** bind explicit ARIA strings: `:aria-selected="activeTab === 'light' ? 'true' : 'false'"`. After rebuilding, accessibility reported `tab (selected) Light` at mount and `tab (selected) Color, Value: on` after keyboard navigation. No source photograph is needed to reproduce this report.

Source follow-up (2026-11-06): the bound-attribute emitter now writes boolean ARIA values as `"true"` and `"false"`. A jsdom tab fixture verifies both states across a click. Packaged WKWebView accessibility remains to be verified.

### Nested conditional component update in Ceiv (2026-11-06)

- **Classification:** confirmed current-source runtime defect in nested conditional component updates; static attributes on custom components are a separate prop-binding requirement.
- **Context:** Lightcept Ceiv's Weiv desktop page, macOS, Weiv checkout `bc512d96d37c567cda92142fec68d6d590bcdf08`. Twelve `DevelopSlider.weiv` instances replaced inline adjustment controls in `App.weiv`.
- **Reproduction:** mount a custom component with a bound numeric prop under a tab panel guarded by `#if`, with the component itself guarded by `#if="developAvailable"`. Update the parent after a photo opens so the tab and component become visible. The generated `App.mjs` refresh calls `refs[174].setProps(...)` for a component reference that has not been mounted.
- **Expected:** the component mounts when both conditions become true and receives current props.
- **Actual:** runtime throws `undefined is not an object (evaluating 'refs[174].setProps')`; the adjustment panel is blank. Always mounting the component under a CSS-hidden wrapper alone did not resolve the blank startup panel while the tab panel remained conditional.
- **Workaround:** keep the three tab panels and their slider children mounted; apply a CSS class to hide inactive panels and unavailable controls. Bind literal custom-component props as expressions (`:id="'exposure'"`), since bare `id="exposure"` was not passed as a prop in this setup.
- **Evidence:** Ceiv packaged build reproduced the failure before the workaround; the rebuilt app displayed the Light controls, and Increase Contrast advanced history from edit 8/8 to 9/9 with the value `+10`. No external issue was submitted.

Source follow-up (2026-11-06): child update regions now return when the handle is absent, and conditional destruction clears the old handle. A nested component fixture covers prop changes while hidden, mount, close, and remount. The original Ceiv conditional layout remains untested with this source change.

### Custom component prop template expression in Ceiv (2026-11-06)

- **Classification:** current-source template expression emitter limitation; whether this is an intended syntax restriction is not documented here.
- **Context:** Lightcept Ceiv's two-layer component split on macOS, Weiv checkout `bc512d96d37c567cda92142fec68d6d590bcdf08`. `DevelopSlider.weiv` passes a help element ID to nested `StepRange.weiv`.
- **Reproduction:** place `:describedBy="`help-${props.id}`"` on a custom component within another `.weiv` component and run the pinned Ceiv build (`src/ui/ceiv/build.sh`).
- **Expected:** the interpolated string is passed as a prop, as similar expressions are accepted on native HTML elements.
- **Actual:** `weiv emit app failed ... error app.emit_failed [bundle] fatal: emit app (UnsupportedTemplateExpression)`. The build gives no source span for the failing expression.
- **Workaround:** define `function helpId() { return `help-${props.id}`; }` in the script and bind `:describedBy="helpId()"`. The pinned Ceiv build then succeeds; the packaged app displayed the nested slider and Increase Contrast advanced history from edit 8/8 to 9/9 with value `+10`.

Source follow-up (2026-11-06): the emitter now rewrites `${...}` expressions in template literals. A mounted parent and child fixture passes the reported `:describedBy` expression and updates it when parent props change. The packaged Ceiv build has not been repeated.

Neiv follow-up (2026-11-10): Neiv `0.1.3` still reproduces
`UnsupportedTemplateExpression` because `app-build.sh` prefers
`packages/neiv/node_modules/weivjs` (`0.1.2`) over the sibling Weiv source. The
Lightcept workaround is to compute the prop in script and bind
`:label="decreaseLabel()"`; the build then succeeds.


## Predictable state contract audit (2026-11-06)

- **Classification:** confirmed current state-model capability gap and diagnostic
  clarity gap, not a new regression. A component's plain scalar assignment and
  tracked object member write have different notification rules. Warning absence
  does not establish tracking safety. Universal wrapper-free updates are a design
  target, not implemented behavior.
- **Context/version:** local Weiv checkout `c8e7443` with existing working-tree
  changes, package metadata `weivjs@0.1.2`; macOS arm64, Bun 1.2.16, Node 22.22.1,
  Zig 0.16.0, jsdom 29.1.1. This is not a published-package verification.
- **Reproduce:** with Zig 0.16.0 first on PATH, run
  `bun test test/component/state-contract.test.ts test/component/jsdom.test.ts test/runtime/observable.test.ts`.
  The minimal component is `test/examples/basic/state-contract.weiv`.
  Dispatch `contract-detached`: its `weivUpdate` callback queues but does not return
  a Promise that later assigns `count = 3`. Wait a microtask: the DOM still shows
  `0`. In a fresh instance, dispatch `contract-object`: two direct `state.count`
  increments inside an external listener update the DOM to `2` after a microtask,
  without a wrapper. The existing `external-callback.weiv` fixture independently
  demonstrates stale scalar state followed by an explicit boundary flush.
- **Expected product contract:** supported component-state writes should notify
  regardless of callback origin, with explicit ownership restrictions and useful
  diagnostics for unsupported cases. Until implemented, document the actual
  boundary contract without implying universal automatic tracking.
- **Actual/error output:** no exception for the stale scalar; the assignment
  succeeds but schedules no update. This silent stale-DOM behavior is the failure
  mode. Object Proxy notifications work independently of scalar boundaries.
- **Workarounds:** put `weivUpdate` around the later scalar mutation, or return
  the Promise from the boundary (flush at settlement, not every intermediate
  await). Shared plain-object/array state can use the existing observable contract;
  raw references and opaque native objects are not thereby made observable.
- **Changes:** package README now states current guarantees and limitations;
  compiler README defines the wrapper-free acceptance gate, including escapes,
  aliases, root replacement, expression semantics, and instance isolation.
  External-callback diagnostics now identify stale DOM risk and show remediation.
  DOM tests characterize async fulfillment/rejection, detached work, synchronous
  exceptions, and external tracked writes. Characterization of a limitation is
  not acceptance of it as the future contract.
- **Tooling friction:** the host default Zig 0.17.0 cannot build this checkout.
  Initial test invocation failed with the complete compiler diagnostic below;
  selecting the already-installed Zig 0.16.0 resolved it (no source workaround).

```text
build.zig:51:11: error: no field named 'args' in struct 'Build'
    if (b.args) |args| {
          ^~~~
/opt/homebrew/Cellar/zig/0.17.0/lib/zig/std/Build.zig:1:1: note: struct declared here
const Build = @This();
^~~~~
referenced by:
    runPackageScript [inlined]: /opt/homebrew/Cellar/zig/0.17.0/lib/zig/std/Build.zig:2144:50
    main: /opt/homebrew/Cellar/zig/0.17.0/lib/zig/compiler/configurer.zig:138:29
    3 reference(s) hidden; use '-freference-trace=5' to see all references
```

- **Architecture placement follow-up (2026-11-06):** proposed semantics and the
  acceptance gate now live in `../weiv-arch/docs/component-state-contract.md`.
  The compiler README retains a reference; the package README retains current
  behavior. The architecture note recommends an ownership/operation matrix before
  a bounded scalar scheduling proof and broader implementation.


## Unified reactive core audit (2026-11-06)

- **Context:** evaluating reuse of `packages/weiv/src/runtime/observable.ts` for
  compiler-owned local state as well as shared state. Checkout `c8e7443` plus
  working-tree changes; package metadata 0.1.2, macOS arm64, Bun 1.2.16,
  Node 22.22.1. Source runtime probes; no released-package claim.
- **Classification:** scalar support and cross-root component-job batching are
  missing capabilities. Native/immutable value handling is a capability and
  validation gap. Raw alias bypass is an inherent Proxy ownership restriction.
  Subscriber failure isolation is a confirmed gap against the proposed shared-core
  contract, not evidence that an existing documented guarantee regressed.
- **Expected:** supported local/shared mutations should enter one notification
  mechanism. Unsupported types should get clear intentional handling. One faulty
  subscriber should not prevent independent subscribers from receiving a change.
- **Reproduction:** from the Weiv root, execute the following with `bun --eval`
  (the import is relative to that root). The uncaught-exception handler is only
  for observing the probe result; it is not an application workaround.

```js
import { observable, subscribe } from "./packages/weiv/src/runtime/observable.ts";
const output = {};
for (const [name, value, op] of [
  ["map", new Map(), x => x.set("a", 1)],
  ["frozen", Object.freeze({ n: 0 }), x => x.n],
  ["date", new Date(0), x => x.getTime()],
]) {
  try { op(observable(value)); output[name] = "accepted"; }
  catch (e) { output[name] = String(e); }
}
const raw = { n: 0 };
const state = observable(raw);
let calls = 0;
subscribe(state, () => calls++);
raw.n++;
await Promise.resolve();
output.rawAlias = { value: state.n, calls };
const shared = observable({ n: 0 });
let first = 0, second = 0;
subscribe(shared, () => { first++; throw new Error("listener failed"); });
subscribe(shared, () => second++);
process.on("uncaughtException", e => {
  output.listenerFailure = { first, second, error: String(e) };
  console.log(JSON.stringify(output));
});
shared.n++;
```

Complete observed output (Bun exits successfully because the probe handles the
uncaught exception):

```json
{"map":"TypeError: Map operation called on non-Map object","frozen":"TypeError: Attempting to define property on object that is not extensible.","date":"TypeError: Type error","rawAlias":{"value":1,"calls":0},"listenerFailure":{"first":1,"second":0,"error":"Error: listener failed"}}
```

- **Workarounds checked:** writes through supported observable plain-object/array
  proxies notify (existing suite: `bun test test/runtime/observable.test.ts`,
  21 pass, 0 fail). Raw-reference writes do not. No new workaround was tested for
  native receivers or listener failures. Adapting unsupported objects into plain
  data and isolating listener errors are proposed remedies, not verified fixes.
- **Source audit:** each observable root owns its pending Map and scheduling bit;
  the compiler emits a separate local Proxy/path queue. Generated components read
  brand metadata and mutate `node.listeners` directly. These are architectural
  findings, not runtime reproduction claims about every cross-root case.
- **Decision/proposal:** use one strengthened core, internal scalar cells,
  component ownership scopes, an internal subscribe/dispose bridge, and explicit
  external adapters. Validate scheduler error/reentrancy/disposal behavior and
  runtime distribution before scalar lowering. Full audit and implementation order
  live in `../weiv-arch/docs/component-state-contract.md`. No runtime semantics
  changed in this architecture follow-up.


## Shared observable scheduler implementation (2026-11-06)

Follow-up to the unified-core audit at `c8e7443` plus working-tree changes.
Environment: macOS arm64, Bun 1.2.16, Node 22.22.1, Zig 0.16.0.

- **Confirmed fix in current source:** the first throwing observable subscriber
  no longer starves subsequent subscribers. Reproduce the earlier listener probe
  or run `bun test test/runtime/reactive-core.test.ts`: both subscribers run, then
  the error is reported as an AggregateError with nested subscriber failures.
  This is not a released-package verification.
- **Scheduling capability added:** observable roots share `reactive-core.ts`.
  Root preparations and subscription membership are captured before delivery;
  reentrant writes wait for a subsequent wave. Owner jobs deduplicate and cancel,
  errors do not starve independent jobs, and a bounded convergence guard stops
  runaway chains. Disposal/re-registration has its own identity to prevent revival
  of a disposed captured registration.
- **Reproduce/validation:** `bun test test/runtime` covers the scheduler,
  observable facade, and router. `bun test test/component` with Zig 0.16.0 covers
  emitted apps and components; the app runtime copies the new transitive module.
  `node packages/weiv/scripts/build.mjs` emits `reactive-core.js`; importing the
  generated observable runtime under Node and writing a subscribed scalar member
  notifies successfully. Vite plugin production build also passes.
- **Still open:** scalar storage, deliberate unsupported-value errors, shared
  subscribe/dispose bridge, and compiler integration. Generated local tracking
  still uses its previous mechanism; generated shared subscribers do not yet use
  owner jobs. No claim that ordinary local scalars now update without wrappers.
- **Architecture status:** details and the remaining migration sequence live in
  `../weiv-arch/docs/component-state-contract.md`, not in compiler implementation
  notes. Existing raw-alias/native/frozen-value audit findings remain unresolved.

- **Final verification for this checkpoint:** 62 runtime tests pass (including 11
  new scheduler/integration cases); 27 component tests pass; `zig build test`
  passes under Zig 0.16.0. After the independent-subscription identity change,
  the runtime suite and focused imported-observable component case pass again.
  `node test/package/reactive-core.test.mjs` builds the packaged runtime and
  exercises notifications through both Vite and Bun production bundles. The
  existing Vite CSS/sibling-component integration test also passes. No new build
  errors were encountered in this checkpoint.


## Internal cells and supported-value validation (2026-11-06)

- **Environment:** `c8e7443` plus working-tree changes, Weiv package metadata 0.1.2,
  macOS arm64, Bun 1.2.16, Node 22.22.1, Zig 0.16.0. Source/build tests only.
- **Confirmed defect fixed:** an existing observable nested in an initial graph
  was not recognized by `ensureObservableNode` because its lookup only covered
  raw targets. Reproduce with `const shared = observable({count:0}); const box =
  observable({value:shared}); box.value`. Expected identity `box.value === shared`;
  previously the read attempted to wrap/brand an already proxied object. Lookup
  now checks raw and proxy maps. The new shared-identity cell tests pass.
- **Missing capability added:** internal cells reuse observable records and the
  shared queue; scopes own subscriptions and deduplicate/cancel render jobs.
  The initial parent edge is established before a first consumer read. Tests cover
  scalar/object/shared batching, replaced-root detach, independent scopes, async
  writes, disposal, cycles, and value validation. `bun test test/runtime` passes
  72 tests; `bun test test/component` passes 27 with Zig 0.16.0. Packaged Vite/Bun
  tests cover scalar and shared-object cells using the same runtime instance.
- **Validation gap addressed:** initial graphs and inserted values now reject
  unsupported native/class/frozen/read-only/accessor objects with explicit
  TypeErrors, before replacing supported state. Getter code is not executed by
  validation. Reproduce with `bun test test/runtime/cell.test.ts` or rerun the
  native/frozen cases from the earlier audit: expected deliberate rejection,
  rather than later native receiver/branding exceptions. Existing raw-alias,
  reflective-operation and other acceptance gaps remain open.
- **Compiler integration gap:** current serialized mutation records use names,
  and the Oxc transpilation stage does not lower bindings to cells. Shadowing-safe
  AST transformation, generated internal runtime resolution, and region/lifecycle
  integration remain required. Detailed findings are in the architecture repo.
- **Test-harness friction (not a Weiv defect):** the first packaged cell fixture
  imported a `file://` URL. Vite 5.4.21/Rollup failed to resolve that URL from the
  temporary entry module with `[vite]: Rollup failed to resolve import
  "file:///Users/chao.yang/Private/weiv/packages/weiv/dist/runtime/cell.js"`.
  Using the absolute filesystem module path, as the existing runtime facade
  already does, fixes the fixture. No adapter or runtime change was needed.


## Experimental lexical cell emitter (2026-11-06)

- **Context/version:** local `c8e7443` plus working-tree changes, Weiv metadata
  0.1.2, macOS arm64, Zig 0.16.0, Rust/Oxc 0.116.0, Bun 1.2.16, Node 22.22.1,
  Vite 5.4.21 and jsdom 29.1.1. No published-package verification.
- **Missing capability addressed experimentally:** `weiv emit js-cells` parses
  original script syntax, resolves lexical identities, lowers supported top-level
  declarations and references to cells, and subscribes local/imported shared
  observables through one ownership scope. It does not change default compilation.
  Reproduce with `bun test test/component/compiler-cells.test.ts` using Zig 0.16.0.
  Actual mounted DOM now updates from external callbacks, between awaits and in
  detached promises without wrappers in this mode. Local+shared writes render once.
- **Fail-closed restrictions:** var/ambient declarations, unsupported declaration
  patterns, destructuring writes, const root writes, top-level await, reserved
  identifiers and eval references are rejected with `Cell*Unsupported` errors.
  Template mutation syntax is parsed and rejected; call script handlers instead.
  Detailed source spans, remaining mutation cases, ownership policy and all-output
  migration remain acceptance work in the architecture repo.
- **Bun interoperability defect observed:** direct identifier calls lowered to
  sequence-expression member calls acquired a receiver under Bun 1.2.16. Minimal
  reproduction: `const box={value:function(){"use strict";return this===undefined}};
  console.log((0,box.value)());`. Execute with `bun --eval`: complete output is
  `false`; the equivalent Node ES module prints `true`. Expected: both print
  `true`. The initial component assertion reported `Expected: true / Received:
  false`. The same happened with `(false, box.value)()`. This is a tooling problem,
  not a claim about browser JavaScript semantics. An internal `unbindCellValue`
  helper uses Reflect.apply, preserving nullish optional calls and evaluating
  arguments before non-callable failures. Component and packaged Vite/Bun tests
  now verify receiver, optional-call and argument-order behavior.
- **Lifecycle issue found by source inspection:** strong observable child-to-parent
  edges retained component cell boxes through long-lived shared values after their
  subscriptions were removed. Edges now use WeakRef, with dead entries pruned on
  propagation. Reproduce the regression check with `bun test test/runtime/cell.test.ts`:
  an isolated process disposes a scope, releases the box, yields, forces Bun GC,
  and confirms collection while the shared value remains usable. This changes
  private graph metadata; mixed-runtime/version compatibility remains a gate.
- **Cold-build test harness:** a new Rust release build exceeded Bun's default
  five-second test limit. Complete primary failure: `Test "experimental compiler
  cells update external writes and preserve lexical shadowing" timed out after
  5876ms (killed 1 dangling process)`. Secondary error: `TypeError:
  modules["CompilerCells.mjs"].mount is not a function`. The isolated prototype
  tests now allow 30 seconds; warm/full-suite runs pass. Build before running other
  existing five-second component tests after compiler changes.
- **Existing CLI output-path tooling issue:** requesting the experimental output
  as `/tmp/weiv-experimental-cells.mjs` hit the common absolute-path directory
  creation path. Reproduction: `weiv emit js-cells
  test/examples/basic/external-callback.weiv /tmp/weiv-experimental-cells.mjs`.
  Expected: write a module. Complete primary diagnostic:

```text
weiv run failed for <process>
  error cli.unhandled_error [bundle] fatal: run (NotDir)
```

  The Zig runner then reported exit code 1 (`4/6 steps succeeded; 1 failed`).
  This is recorded separately from cell lowering; stdout output works and shell
  redirection avoids that CLI directory-creation path. No output-path fix was
  included in this compiler integration.
- **Oxc builder integration:** `expression_call(..., None, ...)` initially failed
  with `error[E0282]: type annotations needed` and `error[E0283]: type annotations
  needed`, because the optional arena allocation has multiple IntoIn conversions.
  Explicit `None::<oxc_allocator::Box<TSTypeParameterInstantiation>>` resolves the
  generic ambiguity. This is expected Rust API typing, not a Weiv runtime defect.
- **Verification:** Rust lowering/validator tests, the full compiler suite,
  component suite, shared runtime/router suite and packaged Vite/Bun generated
  module tests cover this checkpoint. Exact active status, restrictions and next
  acceptance steps live in `../weiv-arch/docs/component-state-contract.md`.

- **Checkpoint counts:** the shared runtime suite passes 73 tests (including the
  new lifetime check); the component suite passes 35 tests, with the eight compiler
  cell cases rerun after additional fail-closed checks. Rust lowering/validation
  has four passing tests. Full compiler tests and Vite/Bun generated-module
  integration pass. The prototype's ordinary-source state requirements remain
  documented separately from default compilation; it is not enabled on release
  paths.


## Module provenance analysis foundation (2026-11-07)

- **Context:** active compilation-boundary goal, checkout `c8e7443` plus working
  changes, Oxc 0.116.0, Zig 0.16.0, Bun 1.2.16 and Node 22.22.1 on macOS arm64.
- **Missing capability addressed:** component script facts were insufficient for
  deciding whether imported state has a notification contract: exports/re-exports,
  initializer provenance and lexical helper dependencies needed a module-oriented
  view. New command: `weiv analyze module-state <path>`. Parsing explicitly reports
  `managed: false`; no transformer ownership is inferred from analyzability.
- **Reproduce:** run `node test/package/module-state.test.mjs` after building the
  compiler. Its temporary module exports an explicit observable, a raw object,
  a primitive constant, helpers with/without a shadowed imported store, and
  aliases/re-exports. Expected: distinct facts, no irrelevant component-props
  diagnostic, no false dependency on the shadowed import. Root reassignments,
  ambient/opaque values and helper calls/mutations remain visible rather than
  being treated as proof of reactivity or purity.
- **Analysis edge case:** TypeScript type-only export declarations can be erased
  from runtime edges, including ambient function declarations exported as types.
  A test initially assumed an ambient runtime record where that export was erased
  (`left: "function", right: "ambient"` for the following runtime binding).
  The cases now distinguish erased declarations from a value export of an ambient
  declaration; the latter retains unknown ownership. This was a test assumption,
  not a confirmed runtime defect.
- **Remaining gap:** the browser dependency collector currently skips imported
  template helper calls. The next resolver must follow lexical module facts rather
  than assuming those calls do not read external mutable state. Recursive graph
  traversal, use-site diagnostics and managed shared-module rewriting are not
  implemented by this fact-extraction milestone. Architecture progress lives in
  `../weiv-arch/docs/component-state-contract.md`.

- **First-milestone verification:** nine Rust backend tests pass, including five
  new module-provenance cases; the new module-state CLI integration test passes;
  `zig build test` passes with Zig 0.16.0. Compiler defaults and runtime behavior
  are unchanged by this extraction API. Rust toolchain: 1.99.0 (b940084d7).

## Lightcept crop controls under a Ceiv native slot (2026-11-07)

- **Classification:** project-specific native-surface interoperability; no confirmed Weiv compiler or runtime defect.
- **Context:** Lightcept `src/ui/ceiv/web/App.weiv` uses a Ceiv 0.1.3 native `NSImageView` in `#photo-preview` inside a Weiv `.stage`. Weiv checkout `c8e7443` plus local working changes; Cyna 0.4.1, Node 22.22.1, macOS arm64. The Ceiv app build and Weiv compilation completed without error.
- **Reproduce:** put a conditional Weiv `<div class="crop-panel">` after `<div id="photo-preview" class="preview">` inside `.stage`, give the panel `position: absolute; z-index: 2`, open a photograph in the built Ceiv app, and activate Crop. The accessibility tree contains the panel's angle slider and buttons, but the screenshot shows only the native photograph. No error output was produced. Expected: the panel is visible over the photograph; actual: the native slot covers the web content despite CSS stacking.
- **Workaround:** place the crop controls in the editor flex layout above `.stage`. The panel becomes visible; the native image still owns crop rectangle drawing and pointer input. This is a Ceiv native-slot compositing limitation for this integration. A future overlay contract should document which surface owns the visual and input stacking order.


## Boundary diagnostics and tracked assignment results (2026-11-07)

- **Context:** active compilation-boundary goal, `c8e7443` plus working changes;
  macOS arm64, Zig 0.16.0, Rust 1.99.0/Oxc 0.116.0, Bun 1.2.16,
  Node 22.22.1, Vite 5.4.21 and jsdom 29.1.1. Not released-package verification.
- **Capability added:** `weiv analyze state-boundaries <component.weiv>` traces
  render dependencies through relative modules, lexical helpers and re-exports.
  Experimental cell emission emits source-located raw/unknown warnings, while
  ordinary emission stays unchanged. Reproduction is
  `node test/package/state-boundaries.test.mjs` after building the compiler.
  The report states `coverage: initializers-and-helper-reads`; complete incoming
  assignment provenance and actual managed shared-module transformation remain
  open. Parsing imports does not establish managed ownership.
- **Re-export identity issue addressed in the new analyzer:** comparing only
  immediate star-export modules would falsely call a diamond of the same original
  binding ambiguous. Resolution now compares originating module/binding identities,
  and keeps unavailable branches uncertain. Tests cover same-origin diamonds,
  distinct-origin conflicts, namespaces and cycles.
- **Subscription gap identified:** a helper can read a known observable without
  exposing a component subscription path. Reproduce with a module exporting
  `function read(){return state.count}` where `state` is an imported observable,
  and render `{{ read() }}`. The current emitter subscribes to direct state values,
  not that hidden publisher. The new resolver reports
  `reactivity.unverified_dependency` rather than declaring the dependency safe.
  This is a confirmed integration capability gap, not yet a hidden-subscription fix.
- **Snapshot normalization defect fixed:** `createCell(snapshot(observable({
  nested:{count:1}})))` previously rejected a supported intentional snapshot with
  `TypeError: Weiv observable state requires extensible objects and arrays`.
  Snapshots are now recognized by the runtime that creates them and pass through
  as frozen values inside cells; ordinary arbitrary frozen values stay unsupported.
  Runtime and mounted-component tests verify retention until explicit recapture,
  and packaged Vite/Bun tests verify common-runtime identity. Mixed runtime-copy
  snapshot recognition is still part of the interoperability gate.
- **Object assignment identity defect fixed:** for selected local state,
  `(state = {}) === state` could be false because a setter returned its raw RHS
  while reads returned the tracked Proxy. Expected: true, and an alias obtained
  from the assignment should notify through the same tracked object. The AST
  lowerer now normalizes RHS values before simple/logical root assignments.
  `bun test test/component/compiler-cells.test.ts` verifies identity, alias writes,
  and logical short circuiting. Packaged Vite/Bun output passes the same checks.
- **Harness syntax correction (not a Weiv defect):** the first loop-shadowing
  fixture used `#for="store of rows"`. Its complete primary diagnostic was
  `error template.invalid_directive [template_parse] [1:11] [10..11] fatal:
  Invalid template directive usage`. Current syntax is `#for="store in rows"`;
  correcting the fixture passes the shadowing check without framework changes.
- **Remaining work:** value provenance after initialization, explicit project
  ownership, live shared-module export preservation, hidden publisher bridges and
  complete runtime distribution. Implementation direction/progress is maintained
  in `../weiv-arch/docs/component-state-contract.md`.

- **Additional provenance hazards covered:** class static state, function properties
  and hidden global reads now produce uncertainty diagnostics. Pure intrinsic
  formatting reads remain quiet. A default-export synthetic name initially shared
  the spelling `$default` with a legal source variable; source inspection showed
  that this could classify an unrelated raw default export using that variable's
  observable initializer. The synthetic token is now unrepresentable as a source
  identifier, and the CLI regression case verifies the raw export is diagnosed.
- **Verification at this checkpoint:** the full component suite passes 37 cases
  and the runtime suite passes 74. Boundary tracing and module-state CLI checks,
  packaged Vite/Bun generated-module checks, TypeScript runtime checks, Rust backend
  tests and the compiler suite are exercised. Broad goal completion remains
  unproven: incoming assignment provenance and managed shared-module compilation
  are still required, and the goal remains active.

## Incoming values and shared-module publisher prototype (2026-11-07)

- **Context:** compilation-boundary goal, `c8e7443` plus working changes; macOS
  arm64, Zig 0.16.0, Rust 1.99.0/Oxc 0.116.0, Node 22.22.1, Bun 1.2.16,
  Vite 5.4.21 and jsdom 29.1.1.
- **Confirmed analyzer gap addressed:** a component with `let state={count:0}`,
  rendering `state.count`, and a callback assigning `state=library.getState()`
  could previously produce no boundary warning because only the initializer was
  inspected. Expected: identify the unverified incoming value. Actual prior output:
  no diagnostic/error. Simple root/member assignment facts now preserve RHS
  lexical ownership and diagnose this path, including parameter inputs and
  shadowed names. Reproduce with `node test/package/state-boundaries.test.mjs`.
  Coverage now explicitly includes simple assignments, not arbitrary alias flows.
- **Confirmed experimental live-import defect addressed:** component setup copied
  imported scalars into constants. After an external write, a script callback or
  refresh could still read the old scalar. Experimental references now use lexical
  import aliases directly; shorthand and shadowed parameters retain their meaning.
  Reproduce with the live-scalar test in `test/component/compiler-cells.test.ts`.
  This fixes stale reads; unmanaged scalars still have no notification publisher.
- **Capability added:** internal explicit module lowering plus companion publisher
  slots preserves source public exports and synchronizes successful root writes.
  Reproduce with `node test/package/module-cells.test.mjs` after building the CLI.
  It checks Vite/Node and Bun bundles and native ESM cyclic initialization. No
  runtime error output occurs on passing runs. A failed source RHS retains its
  original exception and publishes nothing. Canonical module ownership and the
  generated component subscription bridge remain integration gaps, not completed
  automatic shared-module support.
- **Bundler test constraint:** Vite's default older-target class lowering changed
  a class name to `_a` during the first named-evaluation check
  (`AssertionError: '_a' !== 'cls'`). The modern-target fixture passes with
  `build.target: 'esnext'`. This is a test-environment observation, not an isolated
  Weiv defect; broader target compatibility still needs separate validation.
- **Verification:** 114 component/runtime cases and 15 Rust backend cases pass;
  compiler tests, runtime TypeScript checks, module-state/boundary CLI checks,
  and packaged Vite/Bun runtime/module-transform checks pass. The full automatic
  managed-build goal remains active; this is a verified prototype checkpoint.

## Managed app build integration (2026-11-07)

- **Context:** compilation-boundary goal, checkout `c8e7443` plus working changes;
  macOS arm64, Zig 0.16.0, Rust 1.99.0/Oxc 0.116.0, Node 22.22.1,
  Bun 1.2.16, Vite 5.4.21 and jsdom 29.1.1.
- **Capability added:** explicit `emit app-cells` automatically selects render-used
  local/project module state, emits one publisher per canonical selected source,
  and subscribes components through the common scope/scheduler. Private helpers,
  static namespaces, conditional/loop regions and child components now update from
  shared state. Source module exports, live bindings and default snapshots retain
  their JavaScript behavior. Ordinary app compilation keeps its state semantics.
- **Confirmed integration gap fixed:** imported helper calls were deliberately
  omitted from the ordinary runtime region dependency graph. Subscribing a helper
  key without retaining it in the experimental region graph would leave its DOM
  unchanged. Experimental region planning now retains those keys; ordinary region
  planning remains unchanged. Reproduce with `node test/package/app-cells.test.mjs`.
- **Confirmed selection gap addressed in the managed app path:** wrapping every
  visible local declaration also wrapped an unrelated native `Map`. Expected:
  wrap only render-dependent state; actual earlier behavior could throw
  `TypeError: Weiv observable state supports only plain objects and arrays; adapt
  native or class values into plain data`. The managed app now selects locals by
  lexical dependency provenance and leaves unrelated values alone. Standalone
  `emit js-cells` still uses the older broad selection and needs the same policy.
- **Canonical ownership check:** `node test/package/app-cells-boundaries.test.mjs`
  reaches an external library through a project symlink. Expected/actual: raw data
  and private observable helper reads are warned; direct observable imports update;
  the external file gains no publisher. Unused/event-only library imports are quiet.
  Structured warning reports preserve template locations. No error output occurs
  on the passing build except intentional boundary warnings.
- **Implementation/test corrections:** the initial emitted runtime path could point
  one directory above the app (`ERR_MODULE_NOT_FOUND: .../__weiv_runtime/cell.js`).
  Output-relative paths now derive from absolute synthetic output paths. A new
  canonical-path helper also initially erased a sentinel slice type, yielding
  `error(DebugAllocator): Allocation size 93 bytes does not match free size 92`.
  It now preserves the sentinel type; structured diagnostic tests verify stderr
  remains valid JSON. These were prototype defects, not released-package behavior.
- **Verification:** direct emitted apps and Vite/Bun bundles mount and update under
  jsdom. Full component/runtime and compiler suites are retained. Import source
  rewriting uses AST spans, including literal dynamic imports, so import-like text
  inside strings cannot be treated as a dependency. Opaque dynamic module paths
  remain an explicit unsupported pipeline case. Broader incoming aliases, remaining
  mutation-operation gates and runtime-copy compatibility still keep the goal open.
- **Final checkpoint checks:** 114 component/runtime cases and 16 Rust backend
  cases pass, along with compiler tests, module facts and standalone boundary CLI
  tests, both managed-app tests, and existing packaged Vite/Bun runtime/module
  tests. Formatting and whitespace checks pass. Default compilation remains
  unchanged; the full goal remains active for the documented incoming-flow and
  mutation/runtime-interoperability gates.

## Mutation paths, input channels and runtime-copy compatibility (2026-11-07)

- **Context:** active compilation-boundary goal, `c8e7443` plus working changes;
  macOS arm64, Zig 0.16.0, Rust 1.99.0/Oxc 0.116.0, Node 22.22.1,
  Bun 1.2.16, Vite 5.4.21 and jsdom 29.1.1.
- **Confirmed graph defects fixed:** symbol-owned nested writes stopped at the
  parent edge; initial aliases were not linked until read; array length reduction
  left removed children attached. Reproduce with
  `bun test test/runtime/observable-operations.test.ts`. Before correction, symbol
  and alias cases missed expected notifications (for example calls 2 instead of
  3); removed children could produce phantom parent updates. Parent edges are now
  registered eagerly, preserve symbol identity and detach after truncation.
- **Confirmed reflection gaps fixed:** define-property writes previously bypassed
  notifications and descriptor.value exposed raw aliases. Definitions, descriptor
  changes and ordinary writes now share notification logic. Reflect.set retains
  receiver semantics. Native array length conversion, partial failed reductions,
  children inserted during conversion, snapshot sparse lengths/null prototypes/
  __proto__ fields and rejection of unsupported descriptors/immutability are
  covered. Passing tests produce no errors; unsupported operations deliberately
  throw descriptive TypeErrors pointing to snapshot/plain-data alternatives.
- **Confirmed provenance gaps addressed:** destructuring defaults, nested computed
  targets, loop targets and common array/reflective mutator inputs could introduce
  library values after a safe literal initializer without a warning. The facts
  now retain those sources separately, including defaults behind an observable
  RHS. Reproduce with `node test/package/state-boundaries.test.mjs`; expected and
  current output is source-located uncertainty for raw/unknown inputs. Explicit
  contracts and shadowed variables retain their meanings; for-in keys are treated
  as primitives. Remaining opaque aliases/invocations are still an analysis gap.
- **Standalone selection fixed:** `emit js-cells` now uses dependency selection as
  the managed app path does. A helper-rendered alias can update while an unrelated
  native Map remains unwrapped. Reproduce with
  `bun test test/component/compiler-cells.test.ts` using Zig 0.16.0. Reassigned
  callable bindings without a publication path now warn rather than implying
  automatic updates.
- **Runtime interoperability policy implemented:** compatible copies in one realm
  share versioned graph/snapshot/scheduler registries. Reproduce with
  `node test/package/runtime-copies.test.mjs`, which copies the packaged runtime
  twice and also bundles those copies independently. Proxies/snapshots retain
  identity and multiple roots yield one component job. Incompatible/unversioned
  metadata yields `TypeError: Incompatible Weiv observable runtime or realm; use
  one compatible runtime or snapshot() to transfer read-only data`. Explicit
  snapshot transfer succeeds. Mixed-realm live state remains outside this policy;
  the historical ordinary generated bridge is retained pending default migration.
- **Mounted coverage:** `node test/package/app-cells.test.mjs` now includes symbol
  state, literal computed namespace reads, reflective definitions and truncation,
  directly and after Vite/Bun bundling. The larger goal remains active for opaque
  incoming flows and the remaining original acceptance gates.
- **Remaining snapshot callable hazard (confirmed diagnostic/contract gap):**
  `const callback=Object.assign(()=>0,{count:0}); const captured=snapshot({callback});
  callback.count++;` leaves the outer snapshot frozen but exposes count 1 through
  the same callable reference. The direct probe returned
  `{"frozenRoot":true,"sameCallable":true,"visibleCount":1}` with no error output.
  Callable internals/closures remain outside plain-data immutability. The analyzer
  must not infer callable purity or immutable callable properties solely from a
  snapshot factory fact. Preserve callback behavior and diagnose/prove that case;
  do not treat the current snapshot marker as universal coverage.
- **Final verification:** 125 component/runtime cases, 18 Rust backend cases,
  compiler and runtime TypeScript checks pass. Module facts/boundary CLI tests,
  managed app/boundary checks, runtime-copy checks and generated module/runtime
  packages pass, including Vite/Bun. Formatting/whitespace checks pass. The goal
  remains active for callable/opaque incoming-effect and alias-flow guarantees.


## Compilation-boundary follow-up: callable and helper flow coverage (2026-11-07)

- **Context/environment:** experimental `emit js-cells` / `emit app-cells`, checkout
  c8e7443 plus working-tree changes; macOS arm64, Zig 0.16.0, Rust 1.99.0,
  Oxc 0.116.0, Bun 1.2.16, Node 22.22.1, Vite 5.4.21 and jsdom 29.1.1.
- **Confirmed snapshot diagnostic defect, addressed:** snapshot containers preserve
  callable references. Reproduce with `const callback=Object.assign(()=>0,{count:0});
  const captured=snapshot({callback}); callback.count++;` and render
  `captured.callback.count`. Previously the factory marker suppressed warnings;
  now `reactivity.unverified_dependency` explains that wrapping does not track or
  freeze callable properties. Public callback behavior is preserved. Known pure
  inline callbacks and passive plain-data paths remain quiet.
- **Confirmed selection/subscription defects, addressed:** a snapshot callback
  reading a live local scalar previously lacked the correct region subscription;
  a managed raw object inserted into an observable container could retain a raw
  declaration alias. Render-key subscriptions and declaration normalization now
  cover those paths. Reproduce with
  `bun test test/component/compiler-cells.test.ts` (Zig 0.16.0 on PATH), and
  `node test/package/app-cells.test.mjs`. Mounted tests verify independent raw-alias
  cases and local/shared callable updates, directly and with Vite/Bun bundles.
- **Confirmed helper coverage gaps, now diagnosed:**
  `const assign=Object.assign; assign(state,library.getState())` and
  `function forward(target,next){Object.assign(target,next)}; forward(state,next)`
  previously bypassed direct incoming-write facts. Argument-flow diagnostics now
  report unverified incoming mutations/retained aliases. Factory closures retaining
  raw local objects or mutable local scalars warn to create observable state inside
  the helper. Pure local temporary counters and simple read-only helpers stay quiet.
- **Structural provenance gap, partially addressed:** reads such as
  `rows.map(row=>row.callback.count)` and nested template loop equivalents now
  inspect source element paths. Unsupported iterable projections and arbitrary
  helper-result member projections warn conservatively. Complex callback patterns,
  reflective/spread invocation, indirect destination identities and helper-local
  allocations returned by other calls remain analysis gaps, not established
  automatic observability.
- **Reproduction/expected output:** `node test/package/state-boundaries.test.mjs`
  asserts exact warning codes, relevant dependency paths and source locations;
  successful output is `State-boundary tracing, source locations, observable
  contracts, shadowing and cycle diagnostics pass`. Passing tests have no error
  output. Unsupported cases deliberately produce actionable warnings, not silent
  universal coverage claims. `cargo test --manifest-path libs/parser-backend/Cargo.toml`
  checks lexical facts (21 passing cases at this checkpoint).
- Architecture decisions and the requirement-by-requirement acceptance audit remain
  in sibling `weiv-arch/docs/component-state-contract.md`. Ordinary compilation is
  unchanged and the full goal remains active.


## Reflective mutation and retained allocation follow-up (2026-11-07)

- **Environment:** c8e7443 plus working-tree changes, macOS arm64, Zig 0.16.0,
  Rust 1.99.0/Oxc 0.116.0, Bun 1.2.16, Node 22.22.1, Vite 5.4.21, jsdom 29.1.1.
- **Confirmed diagnostic gap, addressed:** render `state.count` from
  `const state={count:0}` and invoke
  `Reflect.apply(Object.assign,null,[state,library.getState()])`,
  `Object.assign(...args)` with `args=[state,next]`, or mutate through a holder's
  destination field. Previous direct-argument facts missed nested/local aliases.
  Expected/current: `reactivity.unverified_dependency` at the template dependency,
  naming the selected state and unverified argument consumer. Local alias prepass,
  structural argument roots and spread/indirection facts cover those cases,
  including aliases reassigned or declared after the consuming closure.
- **Native exemptions narrowed:** destination-mutating native calls use their
  detailed incoming facts only for direct unexpanded identities; source-only and
  read-only arguments remain quiet. Array insertion exemptions require proven
  arrays. Explicit observable/snapshot roots retain their deliberate data contract.
- **Mounted raw-boundary evidence:** `node test/package/app-cells-boundaries.test.mjs`
  now builds a managed module that reflectively inserts a foreign raw child. The
  assignment updates DOM to 1. Foreign `bump()` changes the proxied read to 2 but
  leaves DOM at 1 because the foreign raw alias bypasses notifications. The build
  emits the expected Reflect.apply warning; tests pass without error output.
  An explicit synchronization/subscription bridge remains the integration remedy.
- **Retained allocation diagnostics expanded:** helper-local call results,
  constructors, mutable scalars without initializers and forward lexical captures
  now carry retained-state uncertainty. Primitive conversions remain quiet;
  imported/re-exported explicit observable factories retain their contract.
  Reproduce with `node test/package/state-boundaries.test.mjs` and
  `cargo test --manifest-path libs/parser-backend/Cargo.toml` (24 backend cases).
- **Simple alias-only writes addressed:** `const alias=state;
  alias.child=library.getState()` and equivalent holder/destructured-alias targets
  now retain the incoming source. Rebinding `alias` leaves the old state's contract
  unchanged. Indirect paths remain conservative projections.
- **Remaining analysis gaps:** nested alias target patterns/defaults and loop
  writes, computed callee/result paths, destructured retained helper locals,
  complex callback parameters and structural helper-return contracts. These require
  further selection or actionable diagnostics before claiming complete coverage.
  The goal remains active; ordinary compilation is unchanged.


## Nested aliases and helper-return provenance follow-up (2026-11-07)

- **Environment:** c8e7443 plus working-tree changes; macOS arm64, Zig 0.16.0,
  Rust 1.99.0/Oxc 0.116.0, Bun 1.2.16, Node 22.22.1, Vite 5.4.21, jsdom 29.1.1.
- **Confirmed alias diagnostic gap, addressed:** with `const alias=state`, writes
  such as `({child:alias.child=library.getState()}=observable({}))` and
  `for([alias.child] of library.getState()){}` previously lost the alias destination
  or independent default source. Nested target/default/loop/TS-wrapper traversal
  now retains those sources. Rebinding aliases and for-in primitive key transfers
  keep their existing semantics.
- **Confirmed helper-return gap, addressed for simple lexical returns:**
  `function make(){const captured=snapshot({callback});return captured}` followed
  by `const view=make()` and a template reading `view.callback.count` now diagnoses
  callable properties rather than trusting the outer factory/snapshot alone.
  Simple local aliases/projections and multiple returns carry structural provenance;
  reassigned locals/parameters remain uncertain. Async/generator factories warn
  about Promise/iterator results outside the plain-data contract.
- **Callback subscription gap diagnosed:** a returned callback capturing a helper's
  local observable has no proved subscription merely because that observable
  exists. Requested callbacks now warn on unresolved local captures. Proven primitive
  captures and snapshots of plain literal data remain quiet. Unused returned
  callback bodies do not contaminate sibling data paths; immediate opaque helper
  effects remain diagnosed.
- **Mounted selection/identity evidence:**
  `bun test test/component/compiler-cells.test.ts` (Zig 0.16.0 on PATH) verifies a
  returned raw module/component alias updates through its normalized original
  declaration, a returned root-state callback repaints its consuming key and a
  helper-returned snapshot stays at 0 while its raw source changes. The source
  declaration remains unwrapped solely for that snapshot. `node
  test/package/app-cells.test.mjs` verifies corresponding private module object/
  scalar paths and alias identity directly and after Vite/Bun bundling.
- **Reproduction/verification:** `node test/package/state-boundaries.test.mjs`,
  `cargo test --manifest-path libs/parser-backend/Cargo.toml` (27 backend cases),
  compiler checks and 128 component/runtime cases. Passing checks emit no error
  output; uncertain coverage deliberately emits `reactivity.unverified_dependency`.
- **Default factories and analysis bounds:** named/anonymous default-exported
  functions retain the same return facts. Cyclic/diamond local aliases terminate
  with cycle detection, depth and node budgets; exhaustion retains unknown
  provenance. The bounded-expansion regression passes without error output.
- **Remaining scope:** parameter-dependent returns, complex local destructuring,
  implicit coercion/callable effects and complex callback/result paths still need
  coverage or deliberate uncertainty diagnostics. Direct call-result projections
  remain conservative. The full goal stays active; default compilation is unchanged.


## Parameter and conversion coverage follow-up (2026-11-07)

- **Environment:** c8e7443 plus working-tree changes; macOS arm64, Zig 0.16.0,
  Rust 1.99.0/Oxc 0.116.0, Bun 1.2.16, Node 22.22.1, Vite 5.4.21, jsdom 29.1.1.
- **Parameter-return precision gap addressed:** `function identity(value){return
  value}` no longer needs a blanket unknown-return warning for a known argument.
  Caller arguments preserve lexical module context through helper imports,
  namespace re-exports, forwarding, simple defaults/rest paths and destructuring.
  Expanded positions and reassigned/unknown provenance remain diagnosed. A default
  cannot hide callable properties merely because a supplied snapshot may contain
  undefined; proven non-undefined arguments avoid unused-default warnings.
- **Captured subscription evidence:** `function make(value){return {read:()=>
  value.count}}` can subscribe to a stable managed declaration passed into it.
  Caller alias identity and DOM updates are mounted-tested. Replaced roots,
  callable payloads and unknown computed/inherited native paths remain uncertain;
  a data-only subscription does not observe native function properties. Proven
  own fields named values are not mistaken for native methods.
- **Confirmed implicit-conversion defect addressed:** render `view` from
  `let count=0; const view={toString:()=>String(count)}` and update count from a
  browser callback. Before conversion analysis, DOM stayed 0 while the hook read 1.
  Known toString/valueOf dependencies now select source cells under the consumer's
  key. Native string attributes, template literals, numeric operators and array
  join/locale conversion have mounted cases. Strict identity/Boolean truthiness,
  known unused fallback hooks and locally shadowed String functions remain quiet.
- **Confirmed result-branch defect addressed:** an emitted-app probe for
  `<p>{{ view || "empty" }}</p>` produced
  `{"diagnostics":[],"rendered":"0","current":"1"}` after a callback increment.
  Logical/nullish/conditional/sequence result facts and truthiness/nullishness
  selection now preserve those conversion dependencies. Mounted regressions update
  to 1; statically unused branches do not acquire hook effects. Analysis-limit or
  unresolved result conversion emits uncertainty instead of silently dropping it.
- **Reproduction/verification:** `node test/package/state-boundaries.test.mjs`,
  `bun test test/component/compiler-cells.test.ts` with Zig 0.16.0 on PATH,
  `node test/package/app-cells.test.mjs` and
  `cargo test --manifest-path libs/parser-backend/Cargo.toml` (30 cases).
  The expanded managed app verifies private conversion sources, attributes,
  cross-module parameter identity, one canonical publisher and Vite/Bun bundles.
  Full component/runtime coverage passes 130 cases; passing checks have no error
  output. Unsupported coverage deliberately warns.
- **Remaining scope:** arbitrary direct call-result conversions, native callback
  protocols (including custom JSON serialization) and more precise contextual
  callback/member effects remain acceptance work. Computed conversion keys/custom
  prototypes are deliberately diagnosed. The full goal remains active; ordinary
  compilation is unchanged.

## Direct result and JSON serialization follow-up (2026-11-07)

- **Environment:** c8e7443 plus working-tree changes; macOS arm64, Zig 0.16.0,
  Rust 1.99.0/Oxc 0.116.0, Bun 1.2.16, Node 22.22.1, Vite 5.4.21, jsdom 29.1.1.
- **Confirmed notification defect:** render `JSON.stringify(view)` from
  `let count=0; const view={toJSON:()=>({count})}` and increment count in a browser
  callback. Before this fix the mounted probe returned
  `{"diagnostics":[],"rendered":"{\"count\":0}","current":"{\"count\":1}"}`.
  Known serialization and direct-result conversion hooks now select source cells
  and subscribe the consuming render key. Receiver methods, nested JSON keys,
  helper/method results and numeric conversion have mounted regressions.
- **Imported-observable subscription defect:** a component-local `view.toJSON`
  or `localRead()` that reads a named imported observable needs notifications under
  its consumer key. A mounted unmanaged-library fixture now verifies both update
  after external mutation. Hidden private observables still warn; raw external
  mutation remains outside tracking.
- **Confirmed emitter defect:** template
  `JSON.stringify({toJSON:()=>({count})})` generated invalid
  `JSON.stringify({toJSON:()=>({scope.count})})`. Parser diagnostics were
  `Expected "}" but found "."`, `Expected ")" but found "count"`,
  `Expected ")" but found "}"`, `Expected ";" but found ")"`, and `Unexpected ??`.
  Template rewriting now uses lexical reference identities and source spans,
  preserving shorthand keys and nested callback locals in both emitters.
- **Confirmed nested callback defect:** with `let count=0; const rows=[{count:4}]`,
  render `JSON.stringify(rows.map(({count:local})=>{const next=local+count;return
  {local,next};}))`, then increment count in a browser callback. JSON's shallow
  traversal initially dropped the executed iteration callback: the regression
  reported `Expected: "[{\"local\":4,\"next\":5}]"` and
  `Received: "[{\"local\":4,\"next\":4}]"`. Known iteration callback bodies now
  retain captured dependencies while uninvoked nested function fields stay deferred.
- **Reproduction:** `bun test test/component/compiler-cells.test.ts` and
  `bun test test/component/template-globals.test.ts` with Zig 0.16.0 on PATH;
  `node test/package/app-cells-boundaries.test.mjs` for imported observable updates;
  `node test/package/state-boundaries.test.mjs` for warning/quiet-case contracts.
- **Verification:** 33 Rust backend tests, 132 component/runtime tests, Zig compiler
  checks, module facts/boundary/app checks, and Vite/Bun package checks pass.
  Runtime-copy, module-cell and reactive-core package checks ran sequentially.
  Passing checks have no error output; the reactive-core package fixture retains
  its expected warning for an incoming parameter with unverified ownership.
- **Remaining scope:** custom JSON replacers, unknown layouts, computed/inherited
  protocols and opaque native callback results remain diagnosed. Broader callback/
  member effects and the full ownership/write-form acceptance matrix remain work;
  absence of warnings is not a universal observability guarantee.

## Native spread conversion and template scanning (2026-11-07)

- **Environment:** c8e7443 plus working-tree changes; macOS arm64, Zig 0.16.0,
  Rust 1.99.0/Oxc 0.116.0, Bun 1.2.16, Node 22.22.1, Vite 5.4.21, jsdom 29.1.1.
- **Confirmed syntax/dependency defect:** render `Math.max(...values)` with a
  component-local `values` array. Token scanning treated the spread dots as member
  access and generated `Math.max(...values)` outside the script scope. The mounted
  failure was `ReferenceError: values is not defined` in `updateRegion_text_0`,
  followed by `updateDom`, `instance.update`, `mountIntoBoundary` and `mount`.
  Lexical rewriting now scopes spread operands; binding/dependency/path/inspection
  scanners distinguish spread from property access. A mounted ordinary-compiler
  root-replacement case verifies rendering and subsequent reevaluation.
- **Confirmed conversion defect:** after the syntax correction, use
  `let count=0; const values=[{valueOf:()=>count}]`, render `Math.max(...values)` or
  `Number(...values)`, then increment count in a browser callback. Both probes
  returned `diagnostics:[], rendered:"0"`. With
  `const args=[{toJSON:()=>({count})}]`, `JSON.stringify(...args)` similarly remained
  `"{\"count\":0}"`. Expanded native argument effects now select the actual hook
  sources. Fixed/variadic positions, empty prefixes, numeric/string conversion,
  JSON, property-key conversion and `parseInt` radix have mounted regressions.
- **Helper-forwarding defect:** `function maximum(args){return Math.max(...args)}`
  initially reported spread-layout uncertainty and stayed at 0 for a known array
  of conversion hooks. Root helper invocation effects now resolve parameter/local
  aliases and use the current invocation frame. Cross-module helper forwarding
  updates mounted DOM directly and after Vite/Bun bundling.
- **Mutation boundary:** changing an argument array's length/order can expose a
  different consumed argument. Visible member writes and mutators, including
  `const alias=values; alias.pop()`, now invalidate positional certainty. Unknown
  layouts/iterators and analysis limits diagnose instead of silently claiming full
  coverage from the initializer.
- **Reproduce:** `bun test test/component/compiler-cells.test.ts` and
  `bun test test/component/template-globals.test.ts` with Zig 0.16.0 on PATH;
  `node test/package/state-boundaries.test.mjs` and
  `node test/package/app-cells.test.mjs` for diagnostics and managed/bundled behavior.
- **Verification:** 34 Rust backend cases, 133 component/runtime cases, Zig compiler
  checks, module facts/boundary tests, managed app/external-boundary tests and module
  identity/export checks under Vite/Bun pass. Native operation labels are excluded
  from consumer-binding selection, including a mounted inline-spread case with an
  unrelated local variable named `stringify`.
- **Separate legacy limitation observed:** ordinary compilation of
  `<p>{{ Math.max(...values) }}</p>` with `const values=[1]` and an event-handler
  `values[0]++` can leave the region at 1 while the value becomes 2. Its precise
  path invalidation omits this whole-array consumer. Root replacement reevaluates
  correctly. This pre-existing legacy behavior is recorded; the experimental path
  uses cell invalidation, and this work does not switch default reactivity.

## Helper-produced spread arrays (2026-11-07)

- **Environment:** c8e7443 plus working-tree changes; macOS arm64, Zig 0.16.0,
  Rust 1.99.0/Oxc 0.116.0, Bun 1.2.16, Node 22.22.1, Vite 5.4.21, jsdom 29.1.1.
- **Precision gap addressed:** native spread expansion previously handled known
  array declarations and explicit factories but rejected ordinary helper-returned
  arrays. It now follows a stable helper's single known result through parameters,
  local aliases, imports and helper chains. Its immediate effects remain inspected;
  unsupported layouts still emit `reactivity.unverified_dependency`.
- **Reproduction:** `function argumentsFor(){return [{valueOf:()=>count,
  unused:()=>cache.size}]}` with `let count=0; const cache=new Map()`, rendered as
  `Math.max(...argumentsFor())`. A browser callback increments count. Mounted
  coverage now renders 1 and leaves the unused Map unwrapped. Corresponding
  parameterized/chained and JSON-returned-callback cases pass. This is precision
  work, not a claim that arbitrary library iterators can be inspected.
- **Lifetime constraint:** helper result shapes outlive their expansion calls.
  The argument-analysis operation now owns parameter frames until all consumed
  values/hooks have been inspected, then releases them, within depth/argument/frame
  limits. Ambiguous/multiple results and recursive helpers retain layout warnings.
- **Boundary evidence:** a helper in an unmanaged module returning a conversion
  hook that reads a hidden observable still warns about a missing subscription
  path. Known module/alias identity does not imply access to that private observable.
- **Reproduce/verify:** `bun test test/component/compiler-cells.test.ts` with Zig
  0.16.0 on PATH; `node test/package/state-boundaries.test.mjs` checks quiet known
  helpers, hidden observable paths, ambiguous layouts and recursion. `node
  test/package/app-cells.test.mjs` constructs argument arrays in another managed
  module and verifies private numeric/JSON hook updates, one publisher and public
  exports directly and through Vite/Bun.
- **Remaining callback gap confirmed:** boundary probes for `invoke(()=>count)`
  and `invoke(value=>value.count,raw)` with
  `function invoke(callback,value){return callback(value)}` report
  `helper initialization invokes an opaque callback`. Precise support must preserve
  lexical parameter ownership across supplied callbacks and captured outer values.
  No claim of automatic callback inference is made by this follow-up.
- **Verification:** 133 component/runtime cases, Zig compiler checks, module facts,
  expanded state-boundary checks and managed app/external-boundary checks pass.
  The cross-module helper-array fixture also runs under Vite and Bun. Passing
  checks have no error output; uncertainty fixtures assert their warning contracts.

## Supplied callbacks and parameter ownership (2026-11-07)

- **Environment:** c8e7443 plus working-tree changes; macOS arm64, Zig 0.16.0,
  Rust 1.99.0/Oxc 0.116.0, Bun 1.2.16, Node 22.22.1, Vite 5.4.21, jsdom 29.1.1.
- **Precision gap addressed:** `invoke(()=>count)` and
  `invoke(value=>value.count,raw)` previously diagnosed an opaque callback for
  `function invoke(callback,value){return callback(value)}`. Known supplied/local
  callbacks now retain callee/result facts. Defining function scopes distinguish
  callback parameters, captured factory parameters and nested JSON keys; argument
  evaluation retains its caller context. Template/script parse scopes are separate.
- **Mounted evidence:** a factory-bound callback reading `first.count` plus its
  own `second.count` argument repaints after either source changes independently.
  Callback destructuring/defaults/rest, local callable aliases and returned
  conversion/JSON hooks have cases. An unused callback capturing a Map remains
  unwrapped. Sole proven references skip duplicate broad tracing; repeated uses
  retain their conversion/property warnings.
- **Confirmed emitter defect:** `invoke((value=raw)=>value.count)` generated
  `scope.invoke((scope.value=scope.raw)=>scope.value.count)`. Bun rejected it with
  `error: Invalid binding pattern` at the rewritten arrow parameter. All arrow
  expressions now take the lexical rewrite path. An ordinary-compiler case
  verifies a default parameter shadowing a same-named script variable and later
  event-driven reevaluation.
- **Confirmed diagnostic gap:** forwarding a directly imported observable through
  an unmanaged helper emitted `observable dependency has no direct component
  subscription path`. The component import is a real subscription boundary;
  consumer-key watches now survive contextual callback traversal. A mounted
  external-library fixture updates both an argument callback and a local reader.
  Private external observables still warn and stay outside inferred subscriptions.
- **Analysis robustness:** `invoke(invoke)` with
  `function invoke(callback){return callback(callback)}` initially caused
  `Segmentation fault` during contextual analysis. The captured diagnostic output
  was truncated after 802 lines; its repeated frames were `inspectShape` parameter
  resolution, `convertedCallable`, `convertedResult`, `inspectEffects` and
  `traceInvocation`. Callable-origin cycle detection now warns before recursion;
  visit/depth limits remain backstops. Invocation-local collection avoids expanding
  deferred return trees twice; an 80-level nested-arrow metadata case stays bounded.
- **Reproduce/verify:** `bun test test/component/compiler-cells.test.ts` and
  `bun test test/component/template-globals.test.ts` with Zig 0.16.0 on PATH;
  `cargo test --manifest-path libs/parser-backend/Cargo.toml` for scope/depth facts;
  `node test/package/state-boundaries.test.mjs` for known/unknown/mutating/reassigned
  and recursive callback boundaries. Managed app/external-boundary packages verify
  cross-module callbacks, public exports, one publisher and Vite/Bun consumption.
- **Tooling friction:** the first full component run started while compiler/backend
  rebuilding was active. Its default five-second timeout rejected the first
  `html-entities` test with `Test "static template text and attributes decode HTML
  entities" timed out after 5527ms (killed 1 dangling process)` followed by
  `command failed: emit-js test/examples/basic/html-entities.weiv`. The remaining
  134 cases passed. Prebuild with Zig 0.16.0 before running the full suite; do not
  interpret the cold-build timeout as a template-entity regression.
- **Remaining scope:** callback methods/computed callees, receiver protocols and
  callback-produced iterables remain audit work. The full goal remains active;
  ordinary reactivity is unchanged.
- **Final verification:** after the compiler build completed, the complete suite
  passed 135 component/runtime cases. All 36 Rust metadata/backend cases, Zig
  compiler checks, expanded state-boundary/facts checks, managed app/external
  boundaries and module identity/export checks pass, including Vite/Bun output.

## Callback methods, computed keys and receiver results (2026-11-07)

- **Environment:** c8e7443 plus working-tree changes; macOS arm64, Zig 0.16.0,
  Rust 1.99.0/Oxc 0.116.0, Bun 1.2.16, Node 22.22.1, Vite 5.4.21, jsdom 29.1.1.
- **Precision gap addressed:** `function invoke(value){return value.read()}`
  previously retained an opaque receiver-method warning even for a known ordinary
  object method. Contextual invocation now retains receiver/callee facts. Member
  syntax supplies the receiver; an extracted alias does not. Methods with `this`
  and captured lexical receivers have explicit scope owners.
- **Computed-key gap addressed:** `invoke(holder,"read")` through
  `function invoke(value,key){return value[key]()}` now resolves a known string key
  without analyzing an unused method capturing a Map. Key coercion is separate
  from method invocation. Mutable/unknown keys remain diagnosed; native receiver
  methods without verified callable effects retain an explicit warning.
- **Returned-array coverage:** `Math.max(...invoke(callback))` can consume a known
  callback-produced array. Parameter/receiver frames remain alive until conversion
  hooks in the array have been inspected. A regression with
  `callback({count:100}); return callback(value)` proves the ignored first result
  is not appended to the returned argument list. JSON hooks, helper chains and
  computed methods returning arrays have mounted cases.
- **Deferred-body defect addressed:** adding contextual member calls initially
  produced `wrapped callable property provenance is unknown; wrapping does not make
  its effects reactive` for `Math.max(...invoke(value=>value.read(),observed))`.
  It appeared as a third warning alongside the fixture's two expected raw/private
  external warnings (`3 !== 2`). The outer template traversal had recorded the
  callback body's `value.read()` before invocation. Immediate-depth effect facts
  now defer that body until its own argument scope is available.
- **Reproduce/verify:** `bun test test/component/compiler-cells.test.ts` with Zig
  0.16.0 on PATH; `node test/package/state-boundaries.test.mjs` for known/unknown
  keys, extracted methods, native receivers and ambiguous arrays;
  `node test/package/app-cells.test.mjs` for private receiver hooks across managed
  modules directly and through Vite/Bun; `node
  test/package/app-cells-boundaries.test.mjs` for external observable method writes.
  The raw/private warnings remain, and the observable method consumer updates to 1.
- **Release-gate finding:** source inspection and existing rejection tests confirm
  root destructuring declarations/assignments and inline template writes remain
  unsupported. The architecture now reconciles the numbered acceptance matrix and
  prioritizes root assignment-pattern writes next. Default compilation remains
  unchanged; this follow-up does not claim full JavaScript protocol inference.
- **Verification:** 137 component/runtime cases, 38 Rust backend/metadata cases,
  Zig compiler checks, expanded state-boundary/facts suites and managed app/
  external-boundary/module-export packages pass. The managed app runs directly
  and after Vite/Bun bundling. Passing checks have no error output; the negative
  fixtures assert their explicit diagnostic contracts.

## Assignment patterns and managed import replacement (2026-11-07)

- **Context/version:** experimental compilation-boundary reactivity at Weiv
  `c8e7443` plus this workspace's uncommitted implementation. macOS arm64, Zig
  0.16.0, Rust 1.99/Oxc 0.116, Node 22.22.1, Bun 1.2.16, Vite 5.4.21 and jsdom
  29.1.1. Ordinary compilation's reactivity contract is unchanged.
- **Capability gap addressed:** root object/array assignment patterns and existing
  binding loop targets previously rejected. Experimental lowering now delegates
  destructuring to JavaScript using deferred accessor targets. Each successful
  root write normalizes and publishes independently; the expression retains its
  original RHS. Nested/default/rest/computed/mixed targets, partial getter/default
  failure, IteratorClose, public ESM identity, shadowing, TDZ and anonymous default
  names have functional coverage. Declaration destructuring and inline template
  writes still reject and remain the next implementation work.
- **Confirmed compiler defect:** mounting a managed import also captured its
  initial observable object in another subscription cell. Replacing the live root
  updated the publisher, but mutating the old object still scheduled a component
  update. Minimal store: `export let state={count:0}; export function replace(x){
  return ({state}=x) }`. Render imported `state.count`, retain `old=store.state`,
  call `replace({state:{count:3}})`, await a microtask, then increment `old.count`.
  Expected zero additional component updates. Actual complete assertion output:

  ```text
  AssertionError [ERR_ASSERTION]: Expected values to be strictly equal:

  1 !== 0

    at checkPatterns (test/package/app-cells.test.mjs:122:37)
  actual: 1
  expected: 0
  operator: 'strictEqual'
  ```

  The fix resolves direct imports to their actual export origins after dependency
  selection. An exact selected root uses its publisher exclusively, including
  renamed re-exports. External explicit observables keep direct subscriptions.
  Matching a render key alone was rejected as insufficient because the key may
  also subscribe to unrelated private dependencies. The mounted regression checks
  old-alias detachment, new member writes, partial failure and loop writes directly
  and after both Vite and Bun bundling. Incoming opaque parameter ownership still
  produces an asserted boundary warning.
- **Tooling incompatibility:** Bun 1.2.16 differs from Node on some named
  evaluation/TDZ cases. Reproduce without Weiv using:

  ```js
  let x;
  ({value:x=({["x"]:class {static label=this.name}})["x"]}={});
  console.log(x.name,x.label);
  ```

  `bun -e` prints two empty names; `node -e` prints `x x`. The first mounted
  name/timing comparison failed with this complete semantic diff:

  ```text
  label: ""       // expected "count"
  name: ""        // expected "count"
  trace: ["rhs", "ReferenceError", "get", "ReferenceError", "ReferenceError"]
  // Bun new Function oracle omitted the initial "rhs" effect.
  ```

  The component name/timing regression now runs both native and generated code
  under Node, including a TypeScript assertion target. Module default-class naming
  is asserted under Node; the other pattern/module/app cases run through Bun as
  well. This isolates a tooling limitation; it does not establish Bun name parity.
  A trial exported `__proto__` binding also disappeared from Bun's bundled
  namespace (`actual` lacked `__proto__`, `expected` included it). The naming edge
  fixture retains a private selected `__proto__` binding to isolate the computed
  data-property behavior. No third-party issue has been submitted.
- **Reproduce/verify:** with Zig 0.16.0 on PATH, prebuild using `zig build`, then
  `bun test test/component test/runtime` and `zig build test`; run
  `cargo test --quiet` inside `libs/parser-backend`. Run package scripts
  `module-cells`, `runtime-copies`, `reactive-core`, `module-state`,
  `state-boundaries`, `app-cells` and `app-cells-boundaries` using
  `node test/package/<name>.test.mjs`. Scripts rebuilding the package run
  sequentially. Result: 141 component/runtime cases and 39 Rust cases pass;
  compiler checks and all listed package checks pass. Passing checks have no error
  output; boundary fixtures assert their intentional warnings.

## Sequential destructuring declarations (2026-11-07)

- **Task/version:** continue experimental compilation-boundary reactivity at
  `c8e7443` plus the workspace changes. macOS arm64; Zig 0.16.0, Rust 1.99,
  Oxc 0.116, Node 22.22.1, Bun 1.2.16, Vite 5.4.21 and jsdom 29.1.1.
- **Capability gap addressed:** root `let`/`const` object/array declarations
  previously failed with `CellDeclarationUnsupported`. Sequential generator
  extraction now yields cells or module values to native lexical bindings. Keys,
  defaults, nested patterns, rest and subsequent extraction retain their original
  order; earlier bindings initialize before later steps. A terminal elision
  executes trailing empty patterns and cleanup after the last binding. Runtime
  extraction helpers preserve primitive receivers, ToPropertyKey, symbol/rest
  descriptors, iterator method receivers, skipped values and exception precedence.
  Existing const/import/var/eval restrictions remain. Component top-level await,
  including for-await, is explicitly rejected. Module RHS await is verified;
  await in a selected pattern's computed key/default is unsupported.
- **Confirmed source-selection defect:** the first mounted declaration fixture
  used a named execution source with getters. Generic initializer dependency
  tracing selected that source as state, so mounting failed before extraction.
  Minimal form: `const source={get first(){return 1}};let {first:count}=source;`
  with a template rendering and subsequently updating `count`. Expected: source
  extraction stays ordinary; the extracted supported value is reactive. Error:

  ```text
  TypeError: Weiv observable state requires writable data properties; accessors and read-only properties are unsupported
      at validateObservableValue (packages/weiv/src/runtime/observable.ts:45:13)
      at validateObservableValue (packages/weiv/src/runtime/observable.ts:47:5)
      at observable (packages/weiv/src/runtime/observable.ts:312:3)
      at createCell (packages/weiv/src/runtime/cell.ts:28:16)
      at setup (<temp>/compiled.mjs:299:18)
      at createInstance (<temp>/compiled.mjs:588:16)
      at mountIntoBoundary (<temp>/compiled.mjs:611:20)
      at mount (<temp>/compiled.mjs:638:10)
      at <temp>/check.mjs:3:170
      at ModuleJob.run (node:internal/modules/esm/module_job:343:25)
  Node.js v22.22.1
  ```

  Root declaration metadata now carries per-binding projections/default/rest
  shapes and keeps them after reassignment. Declaration projections differ from
  parameter projections. Execution-only accessor sources stay ordinary; uncertain
  alias ownership warns. Proven plain aliases and explicit observable/snapshot
  factories retain their ownership contracts. Native iterable analysis now also
  diagnoses visible iterator/array changes instead of silently trusting the
  original initializer's element layout.
- **Confirmed rendering defect:** add
  `let {__proto__=0}=Object.create(null)` and render `__proto__`, then increment
  it. The script/native oracle returned `1`, but the template read the ordinary
  scope object's prototype. Complete assertion output (temporary path shortened):

  ```text
  node:internal/modules/run_main:123
      triggerUncaughtException(
      ^

  AssertionError [ERR_ASSERTION]: Expected values to be strictly equal:
  + actual - expected

  + '2 / 3 / 5 / 6 / 4 / 8 / fn / cls / [object Object]'
  - '2 / 3 / 5 / 6 / 4 / 8 / fn / cls / 1'

      at <temp>/check.mjs:5:67 {
    generatedMessage: true,
    code: 'ERR_ASSERTION',
    actual: '2 / 3 / 5 / 6 / 4 / 8 / fn / cls / [object Object]',
    expected: '2 / 3 / 5 / 6 / 4 / 8 / fn / cls / 1',
    operator: 'strictEqual',
    diff: 'simple'
  }
  Node.js v22.22.1
  ```

  The render scope now uses a null prototype. This also corrects ordinary
  compilation's binding-name behavior without adopting experimental reactivity.
- **Declaration failure evidence:** module initialization now publishes individual
  destructured values; selected mixed declaration lists are split at module scope
  so successful scalar initializers publish before later failures. Native and
  managed ESM-cycle fixtures retain earlier initialized exports when a later
  default throws, normal iterator cleanup throws, a trailing empty pattern fails,
  or a later declarator fails. The winning error and event order match, and the
  retained managed object continues notifying after failed module evaluation.
- **Reproduce:** prebuild with Zig 0.16.0 using `zig build`, then run
  `bun test test/component test/runtime` and `zig build test`. Run Rust tests
  with `cargo test --quiet` in `libs/parser-backend`. Package regressions:
  `node test/package/module-cells.test.mjs`, `state-boundaries.test.mjs`,
  `module-state.test.mjs`, `app-cells.test.mjs`, `app-cells-boundaries.test.mjs`,
  `runtime-copies.test.mjs` and `reactive-core.test.mjs` in the same directory.
  Rebuilding package scripts run sequentially. The component oracle checks mounted
  DOM, key/getter/default order, alias identity and original-alias writes, const
  members, rest, names and scalar `__proto__`. Managed app fixtures now initialize
  local/shared state through declarations and run directly and through Vite/Bun.
- **Tooling note:** editing Rust sources during the Bun suite forced a release
  rebuild inside a test's compiler invocation. The resulting complete test error
  was `Test "conditional toggle works with jsdom real DOM" timed out after 5080ms
  (killed 1 dangling process)`, followed by `command failed: emit-js
  test/examples/basic/conditional-toggle.weiv` with empty stderr. Prebuilding and
  rerunning with compiler sources stable passed the full suite. Test timeouts
  were not increased. The previously recorded Bun class-naming limitation remains;
  declaration class-name oracles execute under Node.
- **Remaining scope:** inline template writes and the source-alias lifetime/escape
  audit remain before default adoption. The full implementation goal stays active.
- **Verification:** 146 component/runtime cases and 44 Rust cases pass, alongside
  Zig compiler checks and all package regressions listed above. An independent
  scalar `__proto__` write also repaints correctly. The for-await rejection is
  asserted at the component parser's `script.syntax` stage; direct lowerer coverage
  additionally verifies its `top_level_await` guard.

## Experimental inline handlers and alias lifetime (2026-11-07)

- **Context/environment:** compilation-boundary reactivity in the current dirty
  checkout, experimental `emit js-cells` and managed-app paths. Zig 0.16.0,
  Oxc 0.116, Rust 1.99, Node 22.22.1, Bun 1.2.16, Vite 5.4.21 and jsdom 29.1.1.
- **Missing capability, addressed:** inline template writes previously rejected
  or lacked the script lowerer's lexical cell semantics. Template render/event/
  child callback closures now share script lowering. Immediate render mutations
  and readonly/untracked root writes reject explicitly; ordinary compilation
  retains its existing behavior.
- **Subscription defect, addressed:** source normalization retained subscriptions
  after a receiving root was replaced. Reproduce with `let source={n:0}; let
  state=source`, render state.n, replace state, then mutate source.n. Expected:
  no component job from the old alias. Normalization-only ownership now avoids
  that retained subscription; mounted local/shared/bundled fixtures assert zero
  old-alias jobs. Scalar snapshots remain by-value.
- **Confirmed native-object defect, addressed:** compile and mount a component
  with `const cache=new Map([['key',7]]); let count=0`, render count, and use
  `@click="count=cache.get('key')"`. Expected: Map remains an execution object;
  count captures 7 on click. Actual: incoming-source analysis selected Map for
  observable normalization and mount threw:

  ```text
  TypeError: Weiv observable state supports only plain objects and arrays; adapt native or class values into plain data
      at validateObservableValue (packages/weiv/src/runtime/observable.ts:37:11)
      at validateObservableValue (packages/weiv/src/runtime/observable.ts:47:5)
      at observable (packages/weiv/src/runtime/observable.ts:312:3)
      at createCell (packages/weiv/src/runtime/cell.ts:28:16)
      at setup (<temporary>/CompilerCells.mjs:298:17)
      at createInstance (<temporary>/CompilerCells.mjs:402:16)
      at mountIntoBoundary (<temporary>/CompilerCells.mjs:425:20)
      at mount (test/component/compiler-cells.test.ts:27:49)
      at <anonymous> (test/component/compiler-cells.test.ts:326:52)
  ```

  Opaque execution-only sources now stay raw; unknown ownership retains warnings.
  The mounted regression captures 7, changes Map without changing count, then
  recaptures 8. This does not expand the observable plain-data contract.
- **Confirmed literal corruption, addressed:** setup trimmed lowered script lines
  and removed textual import/export prefixes. A multiline literal containing
  indented `import literal text` / `export literal text` lost content or spaces.
  Component module syntax is now removed in the AST and lowered setup is emitted
  verbatim. The mounted multiline regression checks exact script, render and
  event string values. Shared-module exports use their existing native path.
- **Reproduce/verify:** prebuild with Zig 0.16.0, then run
  `bun test test/component/compiler-cells.test.ts`. The 35 cases include inline
  writes, shadows, handlers, callable replacement, alias jobs, Map and literal
  regressions. Rust backend tests pass all 46 cases. Architecture and remaining
  release gates are maintained in sibling weiv-arch, not the README.
- **Full verification:** 154 component/runtime cases (524 assertions), Zig
  build/tests and all seven module/boundary/app/runtime-copy/reactive-core package
  checks pass. Compiler sources stayed fixed during the full suite; package
  rebuilds ran sequentially.

## Unsupported template writes lacked actionable locations (2026-11-07)

- **Classification/context:** confirmed diagnostics gap in experimental component
  and managed-app emission, current dirty checkout. Zig 0.16.0, Oxc 0.116,
  Rust 1.99, Node 22.22.1, Bun 1.2.16, Vite 5.4.21, jsdom 29.1.1.
- **Reproduction:** create `Child.weiv` containing
  `<template><button @click="count++">go</button></template>` with script
  `const count=0;`. Run `weiv --json-diagnostics emit js-cells Child.weiv`, or
  import/render Child from a parent and run `emit app-cells Parent.weiv out`.
- **Expected:** a fatal readonly-write diagnostic pointing to the original
  `count++` expression in Child, with a useful correction. Multiple failing
  expressions should retain their own locations; valid expressions stay quiet.
- **Actual before correction:** standalone output used `emit.js_failed`, message
  `emit js (CellConstAssignmentUnsupported)`, with null span/location. Managed
  output used `app.cells_emit_failed` at the application root with the same
  lowerer error name; authors had to locate the expression themselves. No runtime
  exception is involved: compilation rejects the write.
- **Correction:** failure-only lexical expression probes produce source ranges
  and remediation for render mutation, readonly/untracked assignment, dynamic
  eval, reserved names and other unsupported expressions. Script-only lowering
  is checked first to avoid false template attribution. Managed emission retains
  the child source path and reports exactly one JSON document. Ordinary emission
  retains its behavior; successful experimental emission adds no probe work.
- **Verification:** prebuild using Zig 0.16.0, then run
  `node test/package/cell-diagnostics.test.mjs`. It covers exact spans/line/column,
  repeated expressions, nested shadows, bindings/conditions/iterables, readable
  text guidance, child paths and both managed command forms. Full verification:
  154 component/runtime tests (524 assertions), Zig build/tests, and eight package
  checks pass. Script-only source-location diagnostics and Bun class naming remain
  separate open acceptance work in sibling weiv-arch.

## Anonymous class wrappers changed native named evaluation (2026-11-07)

- **Classification/context:** confirmed experimental lowering defect plus an
  engine interoperability difference. Base commit c8e7443 with current uncommitted
  reactivity work. Zig 0.16.0, Rust 1.99, Oxc 0.116, Node 22.22.1, Bun 1.2.16,
  Vite 5.4.21 and jsdom 29.1.1.
- **Minimal reproduction:** evaluate
  `({["count"]:class{static label=this.name}}).count.label` with Node and Bun.
  Complete console output: Node prints `count`; Bun prints an empty line. Native
  `let count;({count=class{static label=this.name}}={});console.log(count.label)`
  prints `count` under both. Weiv used the property form to preserve the inferred
  binding name after replacing assignment targets with cell adapters.
- **Additional confirmed semantic defect:** for
  `class{static name(){return "method"};static label=typeof this.name}`, native
  `({count=class...}={})` retains the method and label `function`; the generated
  computed-property form under Node instead gives name `count` and label `string`.
  A static name getter is similarly replaced. These are value mismatches without
  an original runtime exception. The expanded native-oracle regression exposed
  the mismatch when the first attempted correction retained the property wrapper.
- **Expected:** original name descriptors and user name members, before the first
  static initializer; preserve outer binding references without an inner class
  name. A throwing class initializer must leave the receiving binding unchanged.
- **Correction:** classes avoid the property wrapper. An initial static block
  calls internal initializeClassName, which changes only a default empty name
  data descriptor. It uses captured runtime intrinsics, so a user Object binding
  cannot intercept it. Functions/arrows retain property named evaluation. This
  applies to declaration defaults, assignment defaults, component initializers,
  root writes and inline writes. Ordinary reactivity remains unchanged.
- **Reproduce/verify:** prebuild with Zig 0.16.0, then run
  `node test/package/class-names.test.mjs` and
  `node test/package/module-cells.test.mjs` sequentially. The first compares
  mounted/shared bundled execution under Node and Bun with a native Node oracle,
  including descriptors, static order, derived/named classes, custom name members,
  outer aliases, shadowing, __proto__, logical/inline writes and exceptions. The
  module suite removes its Bun class-name skips. Architecture decisions and the
  remaining acceptance gates are recorded in sibling weiv-arch.
- **Full verification:** 154 component/runtime cases (524 assertions), 46 Rust
  cases, Zig build/tests and nine package checks pass. Class names/descriptors
  are asserted in both Vite/Node and Bun execution, including mounted inline
  assignment. Compiler sources stayed fixed during the full component suite;
  package rebuilds ran sequentially.
# Lightcept template global lookup (2026-11-07)

- **Classification:** confusing template API / documentation gap; no compiler defect established.
- **Context:** Lightcept's Ceiv desktop web UI, Weiv checkout `c8e7443`, macOS 15, pinned Cyna compiler `e78889f16b36e9f6eb9d5c6fdcbd69bfede074bc`. A `<select>` for an eight-band HSL editor needed a string value derived from an integer component field.
- **Reproduction:** in a Weiv template, bind `<select :value="String(hslBand)">` with `hslBand = 0`, compile and open the generated Ceiv app, then open a photograph/project so the guarded control renders.
- **Expected:** the selector displays band 0, or the compiler gives a clear diagnostic that built-in globals are unavailable in template expressions.
- **Actual:** the app's status displays `scope.String is not a function. (In 'scope.String(scope.hslBand)', 'scope.String' is undefined)` and the Color panel fails to render the HSL editor. This is the complete runtime error output.
- **Workaround:** bind `:value="hslBand"`; the native select value coercion supplies the string representation. No framework change was needed. The project-specific expression has been removed.

## Original script errors and generated helper collisions (2026-11-07)

- **Context/environment:** experimental compilation-boundary reactivity at
  c8e7443 plus current uncommitted work; macOS arm64, Zig 0.16.0, Rust 1.99,
  Oxc 0.116, Node 22.22.1, Bun 1.2.16, Vite 5.4.21 and jsdom 29.1.1.
- **Confirmed diagnostics gap, addressed:** compile an SFC rendering count with
  script `const count=0;count++;` using `weiv --json-diagnostics emit js-cells`.
  Expected: readonly write at its original script location with a correction.
  Actual before correction: `emit.js_failed`, message
  `emit js (CellConstAssignmentUnsupported)`, with null span/location. Shared
  module failures were similarly reported at the bundle stage. No runtime error
  occurs because emission fails.
- **Correction:** failure-only probes locate the real lowerer's rejection using
  original AST symbols/ranges, before extraction/transpilation/import rewriting.
  SFC scripts and managed shared modules retain their original file/byte offsets.
  Var/ambient declarations, readonly writes, await sites, reserved identifiers,
  component default exports and module syntax have targeted guidance. Unknown
  internal failures retain generic diagnostics without invented source locations.
  Shared var declarations remain raw with a boundary warning in managed builds;
  explicit module-cell selection rejects them. This boundary behavior is retained.
- **Confirmed lexical collision defect, addressed:** create a component rendering
  count with script `let count=0;function setTimeout(fn){return fn()}` and a
  button `@click="setTimeout(()=>count++)"`. `emit js-cells` succeeded, but
  `node --check generated.mjs` produced this complete error (temporary path
  abbreviated):

  ```text
  <temp>/generated.mjs:299
  function setTimeout(fn) {
  ^

  SyntaxError: Identifier 'setTimeout' has already been declared
      at checkSyntax (node:internal/main/check_syntax:74:5)

  Node.js v22.22.1
  ```

  Setup injected timer bindings despite the user's lexical function. The same
  audit found subscription locals named scope/instance shadowing managed roots,
  and Array.from could resolve a user Array binding.
- **Correction:** experimental setup uses native/user timer bindings directly;
  writes already notify independently of callback origin. Subscription internals
  use reserved __weiv_ names and literal spread for dirty sets. Ordinary setup's
  existing timer/subscription path remains unchanged. The mounted local-name
  regression and managed imported-timer fixture exercise scope/instance/Array
  plus all four timer names directly and after Vite/Bun bundling.
- **Reproduce/verify:** prebuild with Zig 0.16.0, then run
  `node test/package/cell-diagnostics.test.mjs`,
  `node test/package/helper-bindings.test.mjs` and
  `bun test test/component/compiler-cells.test.ts`. Exact source locations include
  Unicode, erased TS types, post-extraction writes, shadows and managed child/shared
  paths. Mounted rejection/finally tests verify intermediate updates and writes
  retained after rejection; weivUpdate compatibility tests verify callback results,
  errors and Promise identity without a synchronous flush.
- **Full verification:** 157 component/runtime cases (552 assertions), 49 Rust
  cases, Zig build/tests and 13 package/plugin checks pass. Compiler sources stayed
  fixed during the final component suite; package rebuilds ran sequentially. The
  sibling weiv-arch acceptance ledger retains the required write-by-callback
  matrix as open work; default reactivity remains unchanged.

## Bounded reactivity closure (2026-11-07)

- **Scope correction:** the user explicitly limited completion to the supported
  managed-state contract plus diagnostics outside it. Arbitrary JavaScript effect
  inference, more loading mechanisms and eliminating conservative warnings are
  excluded. The authoritative revised goal/checklist is in sibling weiv-arch.
- **Confirmed async-helper defect, fixed:** the 17-operation/12-context mounted
  matrix initially failed its async/receiver case: `{result:false,trace:[]}` versus
  native `{result:true,trace:[]}`. Experimental setup still replaced async function
  declarations with a callback arrow, discarding a method receiver and changing
  function name/arity. Experimental setup now keeps the native functions; writes
  notify through cells. Ordinary callback wrapping is unchanged. The matrix's
  204 cases pass; helper-bindings additionally checks receiver, name, arity and
  updates between awaits in direct and Vite/Bun managed output.
- **Loading boundary, completed without expanding support:** computed managed
  imports previously rejected as OpaqueDynamicModuleImportUnsupported at the app
  root with no import location/remediation. Original AST import sites now produce
  reactivity.dynamic_module_import at the source module/SFC/template location.
  Component/template dynamic loading is explicitly excluded and rejected with
  guidance to an existing literal loader in a managed JS/TS module or an external
  observable/subscription adapter. The unfinished component literal-loader rewrite
  was removed. Existing module literal-loader support is retained.
- **Reproduce:** after a Zig 0.16.0 prebuild, run
  `bun test test/component/compiler-cells-matrix.test.ts` and sequentially
  `node test/package/helper-bindings.test.mjs`,
  `node test/package/cell-diagnostics.test.mjs`,
  `node test/package/app-cells.test.mjs`. Import negatives cover scripts, handlers
  and render expressions, literal/computed targets, original Unicode/TS offsets
  and shared-module paths. Callback-control/getter/callable uncertainty remains
  explicitly warned rather than being advertised as universally tracked.
- **Environment:** base c8e7443 plus current working tree; macOS arm64, Zig 0.16.0,
  Rust 1.99, Oxc 0.116, Node 22.22.1, Bun 1.2.16, Vite 5.4.21, jsdom 29.1.1.
- **Final bounded verification:** 158 component/runtime tests (1,353 assertions,
  including 204 operation/context cases), 49 Rust tests, Zig build/tests and all
  13 package/plugin checks pass on the final snapshot. Formatting/diff checks pass.
  The bounded milestone is complete; default compilation remains unchanged and
  broader JavaScript inference/loading support is separate future scope.


## Managed-default rollout (2026-11-07)

- **Context/environment:** default CLI, Vite and Bun adoption on base c8e7443 plus
  the working tree; macOS arm64, Zig 0.16.0, Node 22.22.1, Bun 1.2.16,
  Vite 5.4.21. This supersedes the earlier milestone's unchanged-default status.
- **Confirmed packaging defect, fixed:** emitting an app from a directory outside
  the checkout looked for runtime files relative to cwd. The packaged launcher
  now supplies its matching runtime directory through `--runtime-dir`; native
  app emission copies runtime sources from that directory. Reproduce/verify with
  `node test/package/default-reactivity.test.mjs`, which invokes the packaged CLI
  from a temporary external project and mounts the result.
- **Bun tooling limitation:** Bun 1.2.16 exposes `onEnd`/`onDispose` hooks that throw
  as unimplemented when registered. The adapter avoids onEnd and uses process-exit
  cleanup when disposal registration fails. Temporary managed output can remain
  for the process lifetime on that version. The default integration check builds
  and mounts both managed and explicit legacy Bun output.
- **Confirmed adapter gaps, fixed:** Vite hot-update callbacks do not provide the
  Rollup resolve/watch/warn context. The adapter uses the development server's
  resolver, watcher and logger, permits the canonical/generated source roots,
  and performs a full reload after rebuilding the managed graph. The integration
  check edits an original source and verifies the rebuilt graph/reload.
- **Migration compatibility, fixed:** legacy component output synthesizes `.js`
  imports for TypeScript sources. Bundler resolution now maps missing synthesized
  files back to original `.ts`/`.tsx` sources (and Bun's component `.mjs` paths
  back to `.weiv`). Integration tests cover the explicit legacy build path.
- **Local tooling interruption:** Zig reported `NoSpaceLeft` while the generated
  project `.zig-cache` occupied 7.6 GB. Removing only that generated cache restored
  builds; no source files were removed.
- **Final rollout verification:** Zig 0.16.0 build/tests; 171 component/runtime/
  inspection/UI-core tests (1,383 assertions); all 14 sequential package/plugin
  checks; JavaScript syntax and diff checks pass. The first regression invocation
  picked the system Zig 0.17 and failed on the existing build API; rerunning with
  the required Zig 0.16.0 resolved that environment mismatch.


## Legacy reactivity retirement (2026-11-07)

- **Scope:** user authorized immediate retirement without compatibility shims.
  Removed separate emitter paths, synchronous scope snapshots, timer/async
  wrappers, late tracked-root proxies, private observable listeners, `weivUpdate`
  injection/reservation, alternate cells command aliases and plugin mode selection.
  The bounded managed-state contract is unchanged; other repositories migrate
  separately. Props now use the common cell core rather than the old proxy path.
- **Confirmed validation mismatch, fixed:** moving `app-cells` fixtures to ordinary
  `emit app` exposed the old preflight rejecting `./barrel` imports with
  `import.unsupported_runtime_import_type`, although the managed graph already
  supports extensionless project modules. Preflight now defers extensionless
  resolution to that graph; explicit unsupported file types retain diagnostics.
  Reproduce with `node test/package/app-cells.test.mjs` after a Zig 0.16.0 build.
- **Test migration:** former synchronous DOM fixtures now wait for queued batches,
  canonical module checks follow managed outputs, detached promises notify directly,
  and obsolete wrapper characterization is removed. Imported observable sibling
  reads use the existing managed binding granularity; unrelated bindings remain
  isolated. No new JavaScript inference or loading forms were added.
- **Environment:** macOS arm64, Zig 0.16.0, Node 22.22.1, Bun 1.2.16,
  Vite 5.4.21, Rust/Oxc versions unchanged from default adoption.
- **Diagnostic cleanup:** removed obsolete inspector warnings claiming supported
  expression writes, aliases or external callbacks require an owned boundary.
  Mutation and callback facts remain inspectable; uncertain/external ownership
  continues to use the bounded state-boundary diagnostics.
- **Verification:** 170 component/runtime/inspection/UI-core cases (1,376
  assertions), the 204-operation/context matrix, 49 Rust tests, all 14 package
  checks, and the documentation site build pass. Inspector and related package
  checks were rerun after diagnostic cleanup. Zig build and all 119 Zig tests pass;
  retired commands return structured `cli.reactivity_mode_removed` diagnostics
  with migration guidance. Public retirement docs are deployed and verified.
## SVG elements compile into the HTML namespace (2026-11-07)

- **Classification:** confirmed compiler/runtime defect in SVG element creation.
- **Task/context:** Lightcept's Ceiv WebView needed a 200 × 200 RGB curve graph with a grid, polyline, and draggable points in `App.weiv`.
- **Version/environment:** Weiv package 0.1.2, local checkout `eafb27d`; Node 22.22.1; macOS arm64 with Ceiv's WebKit view. The generated source was inspected in `CeivApp.app/Contents/Resources/web/App.mjs`.
- **Minimal reproduction:** compile a component containing `<svg width="200" height="200" viewBox="0 0 200 200"><path d="M0 200L200 0" stroke="red"/><circle cx="100" cy="100" r="5" fill="red"/></svg>` using `npx weiv compile path/to/App.weiv`, then mount it in a browser/WebView. Inspect the generated module's element creation calls and the rendered graph.
- **Expected:** SVG, path, and circle are created in `http://www.w3.org/2000/svg`; the red line and point render inside the 200 × 200 viewport.
- **Actual:** generated code calls `document.createElement("path")`, `document.createElement("circle")`, and likewise for the parent SVG. The graph frame appears but its path and point do not paint. No compiler error was emitted; complete error output: none.
- **Workaround:** use a Weiv managed `<canvas>` and draw the curve with the Canvas 2D API; keep the surrounding controls and state in Weiv. Explicit canvas dimensions and pointer handlers provide the required graph interaction.
- **Lightcept recurrence (2026-11-10):** In the Neiv manual RAW editor, Weiv checkout `1a33328` with Node 22.22.1 on macOS arm64 compiled `<button><svg viewBox="0 0 24 24"><path d="M6 2v14a2 2 0 0 0 2 2h14M2 6h14a2 2 0 0 1 2 2v14" /></svg></button>` using `node ../weiv/packages/weiv/bin/weiv.mjs compile emit app ui/neiv/web/App.weiv /tmp/lightcept-ux-weiv-check-8`. Expected: a visible crop glyph inside the button. Actual: the user saw no icon, and generated `App.mjs` called `document.createElement("svg")` and `document.createElement("path")`; no compiler error was emitted, only the existing `reactivity.unverified_dependency` warnings. A Weiv-owned button with a CSS border-drawn glyph and visible `Crop` label avoids SVG namespace creation and keeps the action accessible.
- **Path check (2026-11-10):** At Weiv `1a33328`, `bun test test/component/svg-namespace.test.ts` passes (Bun 1.2.16, 1 pass). `packages/weiv/bin/weiv.mjs` imports `../dist/run-bin.mjs`, whose `platform.mjs` resolves a source-checkout invocation to `cyna-out/bin/weiv` unless `WEIV_BINARY_PATH` overrides it. Running `node packages/weiv/bin/weiv.mjs emit js test/examples/basic/svg-namespace.weiv /tmp/weiv-svg-path-check.mjs` from the Weiv root emits `document.createElementNS` for `<svg>` and its `<path>`. Thus the current CLI path works. The Lightcept output likely came from an older binary, an override, or a previously generated module; confirm the exact binary and output timestamp in that build before attributing it to a current compiler defect.


## Cyna migration comparison transient formatting input (2026-11-07)

- **Classification:** port-tooling/workflow gap, not a Weiv language/runtime or Cyna formatter defect.
- **Task/context:** native Rust adapter integration; a live normalization comparison was running while the project formatting gate ran in parallel.
- **Version/environment:** Weiv branch `codex/cyna-port`, base `00cd64e9a47e22e30f88e9c049c0f3450c430262`, uncommitted port tools; Darwin arm64, Cyna 0.4.1, Zig 0.17.0, Python 3.13.16. Comparison tooling creates temporary Cyna test roots under `cyna-port/src` for project discovery.
- **Reproduction:** start `python3 tools/test-cyna-normalize.py`; while `cyna-port/src/normalize_corpus_*.test.cy` exists, independently run `cyna fmt cyna-port/src --check`.
- **Expected workflow:** formatting verification reports only persistent source regressions, or the comparison's generated test input already satisfies formatting.
- **Actual:** the temporary generated root is found and fails the formatting gate. Complete output from this occurrence: `cyna-port/src/normalize_corpus_u33bwtts.test.cy`; exit status 1. No persistent source was incorrectly formatted.
- **Workaround verified:** wait for comparison cleanup, then run the whole-source formatting gate; it passes. Keep these two gates sequential. A future harness improvement can format generated input before publishing it for project test discovery.


## Cyna script-fact oracle blocked by Zig allocator API change (2026-11-07)

- **Classification:** Zig-version compatibility gap in the existing Weiv FFI wrapper, not a Rust backend or Cyna decoder defect.
- **Task/context:** compare Cyna typed script facts with `src/compiler/sema/decode_script_facts.zig` using the retained Rust backend. Weiv branch `codex/cyna-port`, base `00cd64e9a47e22e30f88e9c049c0f3450c430262`, uncommitted port; Darwin arm64, Zig 0.17.0, Cargo 1.99.0, OXC dependencies 0.116, Cyna 0.4.1.
- **Reproduction:** create a repository-root Zig test importing `src/ffi/script_backend.zig` and call `analyzeScriptRaw("const x = 1;", "x.ts", allocator)`; run `zig test` with the release Rust archive linked, as attempted by `tools/test-cyna-script-facts.py` before its transport workaround.
- **Expected:** the existing wrapper compiles so the typed Zig decoder can serve as the oracle.
- **Actual, complete compiler diagnostic:**

```text
src/ffi/script_backend.zig:89:35: error: no field or member function named 'dupeZ' in 'mem.Allocator'
    const source_z = try allocator.dupeZ(u8, source);
                         ~~~~~~~~~^~~~~~
/opt/homebrew/Cellar/zig/0.17.0/lib/zig/std/mem/Allocator.zig:1:1: note: struct declared here
//! The standard memory allocation interface.
^
referenced by:
    test.script facts 0: .cyna-script-oracle-is3ni3to.zig:9:49
```

- **Workaround:** the optional oracle calls the unchanged Rust ABI with equivalent scoped input/output ownership, using Zig 0.17 `dupeSentinel(u8, source, 0)` instead of removed `dupeZ`. It still invokes the actual Zig semantic decoder. No production wrapper replacement or general Zig migration is included in the Cyna port.


## Template binding diagnostic coordinate precision (2026-11-07)

- **Classification:** reference diagnostic precision/coordinate-contract gap, preserved numerically during the Cyna port rather than silently fixed.
- **Task/context:** port `src/compiler/sema/bind.zig`; compare diagnostics, not only successful expression resolution. Weiv branch `codex/cyna-port`, base `00cd64e9a47e22e30f88e9c049c0f3450c430262`; Darwin arm64, Zig 0.17.0, installed Cyna 0.4.1, retained Rust/OXC 0.116 backend.
- **Reproduction:** bind template `{{ missing + missing() }}` with no visible `missing` binding and no imported component manifests. The permanent Cyna case "unknown identifiers are diagnosed once per expression using legacy offsets" in `cyna-port/src/template_bind.test.cy` asserts the current ranges; `python3 tools/test-cyna-binding.py` compares the same `binding-edge-0` case with the actual Zig binder. Both checks pass with the legacy values below.
- **Expected:** the first identifier `missing` highlights template byte range `[3,10)`.
- **Actual binding diagnostic:** severity `error`, kind `unresolved_binding`, name `missing`, message `Unresolved template binding`, span `[0,7)`. The expression source itself starts at byte 3. The binder adds the identifier offset within trimmed expression text to the enclosing node span, omitting the expression's own source offset. There is no compiler crash; complete error payload is the diagnostic just listed.
- **Related coordinate ambiguity:** `framework.reserved_binding` uses script-binding-relative coordinates, while ordinary binding diagnostics use template-relative coordinates. The Zig diagnostic record has no field identifying that origin. This is visible in the binder's script-binding validation path independently of the interpolation precision issue.
- **Port policy/refinement:** keep legacy numeric ranges/order/messages for parity. Cyna's diagnostic model adds explicit `BindingSource.template` / `.script` metadata, and the binder already retains exact expression source spans. A later precision fix can use those spans and the compilation owner's source mapping, with separate compatibility tests. Source-origin metadata is an architectural addition; it does not claim that existing numeric highlighting is corrected.


## Template-function mappings can select an earlier equal substring (2026-11-07)

- **Classification:** confirmed source-mapping precision defect in the Zig collector, separate from binding diagnostic offsets.
- **Context/environment:** Cyna template-function port on `codex/cyna-port`, Weiv reference `00cd64e9a47e22e30f88e9c049c0f3450c430262`; Darwin arm64, Zig 0.17.0, Cyna 0.4.1/LLVM 22.1.2, retained Rust backend/OXC 0.116.
- **Reproduction:** parse/normalize `<a #if="a">{{a}}</a>{{a}}`, then walk `src/compiler/lower/template_functions.zig`'s Collector with `include_pure = true`. `python3 tools/test-cyna-template-functions.py` includes this case, runs the unchanged collector through the retained Rust ABI, and separately checks exact expression pointer offsets. The optional Zig 0.17 adapter uses `dupeSentinel` as documented above.
- **Expected:** the conditional function's template mapping points at the condition expression `[8,9)`.
- **Actual:** `std.mem.indexOfPos(template, node.span.start, expression)` selects the tag name at `[1,2)`. Generated function text is correct; its original-source mapping is wrong. No diagnostic/crash is produced; the complete incorrect mapping payload is `template: { start: 1, end: 2 }` instead of `{ start: 8, end: 9 }`.
- **Port refinement/workaround:** Cyna's lexical input model keeps parser-provided expression spans and uses them directly. Generated function bytes and generated ranges still match the original Zig collector. An independent oracle changes only the search to source-pointer offset subtraction and checks corrected numeric ranges. Across 77 components plus 16 targeted cases in both collection modes, nine emitted mapping records differ from the legacy search. Production Zig source remains unchanged; the report is ready for its own precision fix.


## Tracked-path scanner includes quoted/commented paths for referenced roots (2026-11-07)

- **Classification:** confirmed path/dependency precision defect in browser tracking, preserved for this port's compatibility gates.
- **Context/environment:** Cyna tracked-root/path port on `codex/cyna-port`; Weiv reference `00cd64e9a47e22e30f88e9c049c0f3450c430262`, Darwin arm64, Zig 0.17.0, Cyna 0.4.1 with LLVM 22.1.2, retained Rust/OXC 0.116 script backend.
- **Reproduction:** define a visible noncallable immutable `root` object with no alias target or whole-binding mutation, bind template `{{"root.quoted" + root.value}}`, and call `tracked_paths.Table.collectExpressionIds` with that LIR expression. `python3 tools/test-cyna-tracked-paths.py` includes this as `tracked-edge-7`, compares the actual Zig classifier/table, and also exercises comment paths (`tracked-edge-8`). The native case "legacy bound scanner keeps quoted paths when the same root is referenced elsewhere" uses the equivalent single-quoted expression.
- **Expected:** track the actual member read `root.value`; canonical paths are `root` and `root.value`, with only the member leaf returned.
- **Actual, complete relevant result:** roots `[{ id: 1, binding_name: "root", kind: "local-tracked" }]`; paths `[{ id: 1, root_id: 1, path: "root", parent_path_id: null }, { id: 2, root_id: 1, path: "root.quoted", parent_path_id: 1 }, { id: 3, root_id: 1, path: "root.value", parent_path_id: 1 }]`; expression leaf IDs `[2, 3]`. There is no compiler error or diagnostic.
- **Cause/evidence:** the scanner does not skip strings/comments. Its LIR bound-fact check validates root-name presence for the whole expression; `root` passes because of `root.value`, which also admits the quoted `root.quoted` occurrence. With no bound reference to `root`, a bound expression is filtered correctly; unbound fallback expressions have no bound-name filter.
- **Workaround/port policy:** preserve numeric IDs and scanner behavior so region/metadata parity remains assessable. Keep discovery in its own operation and record the discrepancy rather than silently substituting the template binder scanner, whose quote and keyword behavior differs. A future precision fix should inspect syntax/token occurrence identity and update shared browser emission/inspection expectations together. No production Zig change is included here.


## Dependency helper lookup expands shadowed script callables (2026-11-07)

- **Classification:** confirmed lexical binding-identity precision gap in browser dependency analysis, preserved during this port.
- **Context/environment:** dependency analysis on `codex/cyna-port`, reference Weiv `00cd64e9a47e22e30f88e9c049c0f3450c430262`; Darwin arm64, Zig 0.17.0, Cyna 0.4.1/LLVM 22.1.2, retained Rust/OXC 0.116.
- **Reproduction:** compile template `<i #for="f in items">{{f()}}</i>` with visible `items`, `a` and script helper `function f(){return a;}`. Collect dependencies for the loop subtree using `dependencies.collectNodeDeps`. `python3 tools/test-cyna-dependencies.py --targeted-only` includes the full backend/binder/render-tree path in `dependency-edge-16`; native test "legacy name-only callable lookup expands script helpers shadowed by loop locals" uses equivalent typed facts.
- **Expected:** the call resolves to loop-local `f`, so it must not expand the unrelated script helper's read of `a`. Before external-binding filtering, the loop dependencies can include `items` and local `f`; script `a` is not read by this template call.
- **Actual, complete relevant dependency payload:** `items: ["items", "f", "a"]`. Visible-binding compaction retains the same names because it also checks names without lexical identity. No compiler error or diagnostic is emitted.
- **Cause/evidence:** the collector's call path finds a visible script binding by name and expands helper facts before consulting supplied loop locals. Bound references retain names/call flags but no resolved binding identity, so the same ambiguity also affects compaction and other name-based consumers.
- **Port policy/workaround:** keep Zig order/closure behavior in the dependency parity contract and record a focused regression. Treat lexical binding identity as a separate correction across binder facts, dependency/helper selection and visible compaction; checking only textual equality or replacing a scanner is insufficient to fix all stages. No production Zig behavior was changed here.


## Scoped CSS preserves unsupported group contents and misreads comment braces (2026-11-07)

- **Classification:** scoped-CSS capability/precision gaps in the Zig reference, preserved in the Cyna port's compatibility contract.
- **Context/environment:** browser assembly/CSS port on `codex/cyna-port`, Weiv reference `00cd64e9a47e22e30f88e9c049c0f3450c430262`; Darwin arm64, Zig 0.17.0, Cyna 0.4.1/LLVM 22.1.2. Scope IDs use the same seed-zero Wyhash algorithm in both implementations. The CSS oracle itself does not need the Rust backend; the Cyna end-to-end test retains it for component compilation.
- **Reproduction:** `python3 tools/test-cyna-css.py` compares `emitScopedCss` and emit diagnostics for all components plus focused styles. `css-edge-23.weiv` contains `@container x{p{color:red}}`; `css-edge-29.weiv` contains `p { /* } */ color:red; }`. Handwritten Cyna tests additionally exercise the equivalent public low-level rewrite with scope selector `[s]`.
- **Container expected:** scope the qualified rule inside the group, e.g. `@container x{p[s], [s] p {color:red}}` for `[s]`.
- **Container actual, complete CSS:** `@container x{p{color:red}}`; no diagnostic. `shouldRecurseAtRule` recognizes only `@media`, `@supports` and `@layer` prefixes, so valid container groups retain unscoped inner selectors. `@scope` groups similarly remain raw. This can let those selectors affect elements outside the component.
- **Comment expected:** ignore the `}` inside `/* ... */` and emit `p[s], [s] p { /* } */ color:red; }`.
- **Comment actual:** `UnterminatedRule`; fatal emit diagnostic code `style.unterminated_rule`, severity `error`, message `Unterminated scoped style rule`, with the whole style content's full-file byte span. There is no additional compiler diagnostic. `findMatchingBrace` handles quoted strings but counts comment braces as structural braces. An opening comment brace (`css-edge-30`) can also make valid CSS appear unterminated.
- **Related compatibility boundary:** prefix-based recursion also scopes `@mediax{p{}}`, yielding `@mediax{p[s], [s] p {}}` with `[s]`, despite `mediax` not being the recognized `media` keyword. Whole `:global(...)` selectors unwrap; mixed global selectors and nested qualified-rule bodies retain the reference's limited treatment.
- **Workaround/port policy:** no container-scoping workaround was adopted; the recursion policy leaves the container body raw. For comment braces, removing the brace-bearing comment or placing comments outside rule blocks avoids the reproduced failure. The port does not change either behavior: iterative CSS traversal and explicit scope-ID calculation keep a separate place for a later token-aware precision/capability fix. Production Zig code is unchanged.


## JavaScript import emission can produce invalid module syntax (2026-11-07)

- **Classification:** confirmed reference code-generation defects, preserved by the Cyna compatibility slice.
- **Context/environment:** Weiv `00cd64e9a47e22e30f88e9c049c0f3450c430262`, `codex/cyna-port`, Darwin arm64, Zig 0.17.0, Cyna 0.4.1/LLVM 22.1.2. The affected operation is `src/compiler/backend/browser/emit/js_module/imports.zig`.
- **Reproduction:** supply an import record with kind `side_effect`, source `./quote".ts`, local name empty; separately supply kind `side_effect`, source `./Card.weiv`, local name empty. Call preserved-import emission with no overrides. Permanent Cyna regression: "reference import output preserves unescaped specifiers and empty component side-effect aliases" in `cyna-port/src/javascript.test.cy`; the operation transcribes the Zig branch ordering and literal interpolation.
- **Expected:** JavaScript-escape source specifiers; preserve a side-effect component import without requiring a namespace identifier.
- **Actual, complete output for each input:**
  ```js
  import "./quote".js";
  ```
  ```js
  import * as  from "./Card.mjs";
  ```
  Each output has a blank line after the import. Neither is valid module syntax. The reference operation emits no diagnostic: specifiers are interpolated raw, and the `.weiv` branch precedes side-effect handling.
- **Workaround/port policy:** avoid quote-bearing specifiers and use a named component import where appropriate; explicit safe import overrides can avoid the quoting case. The port retains exact output for parity. A separate fix should share the JavaScript string writer and handle side-effect imports before namespace lowering.

## Template parser rejects HTML comments (2026-11-07)

- **Classification:** reference template syntax capability gap.
- **Context/environment:** same Weiv reference and host/toolchain as above. Discovered while constructing the static module oracle fixture.
- **Reproduction:** call the actual Zig `parseTemplate` on `<!-- comment -->text` (or place those bytes inside a component template); the original targeted fixture in `tools/test-cyna-javascript.py` failed in parsing before emission and was replaced with a valid custom-element fixture.
- **Expected:** ignore the HTML comment and retain text, or explicitly diagnose unsupported comment syntax.
- **Actual, complete parser failure:** `MismatchedCloseTag`. No module is emitted; this is a parser failure rather than a JavaScript emitter mismatch.
- **Workaround/port policy:** omit HTML comments in current templates. This packet does not extend template syntax or silently correct the reference parser during an emission port.
## Cyna browser emission crashed when traversing owned subscriptions (2026-11-08)

- **Classification:** Cyna port integration and ownership traversal problem. The evidence identifies a reliable workaround; a standalone Cyna compiler defect has not been reduced or confirmed.
- **Context/environment:** Weiv `00cd64e`, branch `codex/cyna-port`; macOS arm64, Cyna 0.4.1 with LLVM 22.1.2, retained Rust/OXC backend. The project builder selected a local cell for `count` and an imported observable for `shared` in `test/examples/basic/compiler-cells-import.weiv`.
- **Reproduction:** on the pre-fix `emit_setup.cy` implementation, run `cyna run cyna-port -- build-browser test/examples/basic/compiler-cells-import.weiv /tmp/weiv-cyna-imported-project`. A reduced component with `<template><p>{{ count }}</p></template>` and script `import { shared } from "./state.mjs"; export let props = {}; let count = 0;` also crashed. Removing the named import or emitting without the selected local subscription avoided the crash.
- **Expected:** emit the component module, local `count` watcher, imported `shared` watcher, and local JavaScript dependency.
- **Actual, complete CLI failure:** `error: NativeRunFailed` after `warning: overriding the module target triple with arm64-apple-macosx26.0.0 [-Woverride-module]` and `1 warning generated.` A directly built executable exited 133 with no output. LLDB stopped in `libsystem_malloc.dylib` `_xzm_xzone_malloc_freelist_outlined`; its stack ran through `cyna_fmt_append_bytes`, `ref_name`, `create_element`, `emit_nodes_into`, and `emit_with_selection` after setup emission. The crash location was downstream of the suspected ownership problem.
- **Workaround/verification:** replace by-value loops over `selection.local_subscriptions`, `selection.managed_subscriptions`, and script imports in setup emission with indexed borrowed reads. The original fixture then builds; Bun/jsdom verifies its local and imported values change from `0 / 0` to `1 / 1` after `cells-mixed` and a scheduler flush. `cyna test cyna-port --jobs 2` passed 394 tests. No external issue was filed.

## Cyna browser output needs a prepared runtime directory (2026-11-08)

- **Classification:** package integration gap in the Cyna port; the runtime source and JavaScript package build work, while automatic runtime preparation in the Cyna CLI is missing.
- **Context/environment:** Weiv `00cd64e`, branch `codex/cyna-port`; macOS arm64, Cyna 0.4.1/LLVM 22.1.2, Bun 1.2.16, retained Rust/OXC backend. The canonical runtime is `packages/weiv/src/runtime/*.ts`, and `packages/weiv/scripts/build.mjs` transpiles it to six `.js` files under `packages/weiv/dist/runtime`.
- **Reproduction:** from the repository root, run `cyna run cyna-port -- build-browser test/examples/basic/compiler-cells-import.weiv /tmp/weiv-cyna-output` and inspect the emitted imports. The Cyna project emits `"weiv:cells"` in the component and `"weiv:observable"` in its copied dependency. A plain browser module loader cannot resolve either specifier. There is no CLI diagnostic because this mode expects bundler resolution.
- **Expected:** a standalone browser build contains the runtime modules and relative imports without requiring a separate source rewrite.
- **Workaround/current behavior:** run the package build (`npm run build --prefix packages/weiv`), then pass `packages/weiv/dist/runtime` as the optional fifth `build-browser` argument. The CLI copies the six files into `__weiv_runtime` and rewrites parsed import literals. `python3 tools/test-cyna-project.py` verifies the written modules in Bun/jsdom without editing them. Automatic runtime preparation and package discovery remain open; no external issue was filed.
## Cyna package preview writer was missing (2026-11-09)

- **Classification:** Missing Cyna port capability and package integration gap; no confirmed Weiv or Cyna compiler defect.
- **Task/context:** Run the existing `weivjs` package E2E test with the standalone Cyna port binary selected through `WEIV_BINARY_PATH`.
- **Versions/environment:** Weiv `00cd64e` on `codex/cyna-port`, Cyna 0.4.1, Zig 0.17.0, Node 22.22.1, Bun 1.2.16, macOS arm64. The retained Rust script backend is built from this checkout.
- **Reproduction:** `cyna build cyna-port --output /tmp/weiv-cyna-package-candidate`, then `WEIV_BINARY_PATH=/tmp/weiv-cyna-package-candidate node test/package/package-e2e.test.mjs` from the Weiv root. The test installs the local package in a temporary consumer and invokes `npx weiv --help` followed by `npx weiv compile emit app App.weiv ./dist`.
- **Expected:** The package test produces `dist/App.mjs`, `dist/bundle.mjs`, `dist/index.html`, and `dist/server.ts`, then completes as with the Zig binary.
- **Actual, complete decisive error:** `Error: Command failed: npx weiv compile emit app App.weiv ./dist` with exit status 2. The Cyna binary prints `Usage: weiv-cyna build-browser <entry.weiv> <out-dir> [runtime-dir] | emit-js <entry.weiv> | emit-css <entry.weiv> | emit-module-cells <module> <companion> <bindings-json> | inspect-project <entry.weiv> | inspect-lir <entry.weiv> | inspect-render-tree <entry.weiv>` because it has no `compile emit app` command or preview output writer.
- **Current disposition:** `compile emit app` and `emit app` now generate preview entry, HTML, props, package and server files from the Cyna project build. With `WEIVJS_PACKAGE_SPEC=/Users/chao.yang/Private/weiv/packages/weiv` and `WEIV_BINARY_PATH=/tmp/weiv-cyna-package-candidate`, `test/package/package-e2e.test.mjs` passes; a direct Bun/jsdom preview mount and click also pass. Preview props and server output now match Zig on focused fixtures. The installed registry package is older and carries only two runtime files, so it is not a valid test of the current six-file runtime contract.

## Installed Cyna 0.4.1 crashes while reporting missing runtime files (2026-11-09)

- **Classification:** Confirmed installed Cyna toolchain failure during a Weiv integration error path; consistent with Cyna LG-31 (imported typed-failure trace context omitted in the installed release). The current Cyna source checkout records LG-31 as fixed but unreleased. This report does not establish a new independent compiler defect.
- **Context/environment:** Weiv `00cd64e` on `codex/cyna-port`, installed Cyna 0.4.1 with LLVM 22.1.2, macOS arm64, Node 22.22.1. `cyna build cyna-port --output /tmp/weiv-cyna-package-candidate` produces the affected binary. The registry `weivjs` 0.1.2 package runtime has `observable.js` and `router.js`; the current writer requires `binding.js`, `cell.js`, `index.js`, `observable.js`, `reactive-core.js`, and `router.js`.
- **Reproduction:** Run `/tmp/weiv-cyna-package-candidate build-browser /tmp/weiv-cyna-preview-repro/App.weiv /tmp/weiv-cyna-missing-runtime-debug <registry-package>/dist/runtime` with a valid component and that two-file runtime directory. The same failure occurs via `WEIV_BINARY_PATH=/tmp/weiv-cyna-package-candidate node test/package/package-e2e.test.mjs` when the test installs registry `weivjs` 0.1.2.
- **Expected:** A typed filesystem error reaches the CLI and it exits with a readable missing-runtime message.
- **Actual, complete decisive output:** The process exits 139 (`SIGSEGV`) with no CLI output. LLDB stops at `lock_context` in `failure_trace.c:24` with `EXC_BAD_ACCESS (code=1, address=0x10)`. The crash is on error unwinding after a required runtime file is absent.
- **Workaround/verification:** The CLI now checks all six files before entering the writer and prints `Cannot write browser project: runtime directory is missing required files`, exiting 1. The current local package build includes all six files and passes package E2E. The source Cyna fix for LG-31 has not yet been adopted by the installed 0.4.1 binary.
## Preview prop scanner hit Cyna optional slice return rejection (2026-11-09)

- **Classification:** Confirmed Cyna compiler semantic defect, tracked as Cyna LG-66; the Weiv workaround is an owned result string.
- **Context/environment:** Weiv `codex/cyna-port` at `00cd64e`, macOS arm64, installed Cyna 0.4.1 and source checkout compiler `387d56f7`.
- **Reproduction:** Put `fn maybe_slice(value: []const u8): ?[]const u8 { if value.len() == 0 { return none; } return value; }` in a Cyna file and run `cyna check` on it. The full minimal file and both compiler outputs are recorded in Cyna `docs/LANGUAGE_GAPS.md` LG-66.
- **Expected:** `return none` is accepted for a `?[]const u8` result under SPEC §11.2.
- **Actual:** `error: \`none\` requires an expected optional type` at the `return none` statement.
- **Workaround/verification:** `preview_props.cy` returns `?string` and copies the found interface body. The Weiv project checks, and generated props match Zig byte for byte on `basic-counter.weiv`, `CardUsage.weiv`, `EmptyStateUsage.weiv` and `imported-ts-helper/App.weiv`.
## Removed `weivUpdate` wrapper compiles without an unresolved-binding diagnostic (2026-11-09)

- **Classification:** compiler validation gap for removed API usage, exposed during the Neiv desktop integration.
- **Context/environment:** Weiv `ed71d0e` on `main`; macOS arm64; Neiv host `WKWebView`; the component called the removed global `weivUpdate` API inside 114 assignments.
- **Reproduction:** compile a `.weiv` component whose script calls the undefined global `weivUpdate(() => { count += 1; })`, then invoke the generated event handler. Use the full Lightcept command `node ../weiv/packages/weiv/bin/weiv.mjs compile emit app src/ui/neiv/web/App.weiv src/ui/neiv/build/web-open-fix-2`.
- **Expected:** report an unresolved `weivUpdate` binding at compile/check time, or emit the documented migration diagnostic for the removed API.
- **Actual:** compilation exits successfully with 22 unrelated dependency warnings and emits `App.mjs` containing calls to `weivUpdate`. At runtime, clicks invoke the handler, the async callback rejects with `ReferenceError: Can't find variable: weivUpdate`, and the UI remains unchanged. There is no visible error in the app.
- **Workaround/verification:** define `function weivUpdate(update: () => void) { update(); }` in the component, recompile, and verify the central Open Photo button opens the native file picker. A direct migration that removes all 114 wrappers is preferable; static rejection of the removed global would have made the migration failure immediate.
- **Update (2026-11-10):** Lightcept removed the shim and all 114 wrappers. The page now compiles in managed mode with the same 22 pre-existing dependency warnings, the generated `App.mjs` contains no `weivUpdate` calls, and the Neiv bundle rebuilds successfully.

## Affon performance report `weiv compile` fails without a diagnostic (2026-11-10)

- **Classification:** tooling/diagnostics gap; confirmed failure, root cause not reduced.
- **Task/context:** Regenerate `test/benchmark/results/performance-report.html` from the checked-in Affon `test/benchmark/report/App.weiv` (163 lines) after promoting CUDA reduction cells. Only the injected props payload changes; the template is unchanged.
- **Versions/environment:** Weiv `1a33328` on `main`; macOS arm64; Node `22.22.1`; Bun `1.2.16`; CLI at `/Users/chao.yang/Private/weiv/node_modules/.bin/weiv`; Affon checkout `/Users/chao.yang/Private/affon`.
- **Reproduction:** `mktemp -d /tmp/affon-weiv-repro.XXXXXX`, then `weiv compile test/benchmark/report/App.weiv <temp-dir>` from the Affon repository root.
- **Expected:** emit the browser project (including `main.mjs`, `report.mjs`, and `styles.css`), as the checked-in report was previously built.
- **Actual:** exit status `1`; stdout is exactly `Cannot build browser project: browser emission failed`; stderr is empty; nothing is written to the output directory. No module, file, line, or underlying error is identified.
- **Workaround/verification:** Reuse the previously compiled bundle and CSS from the checked-in `performance-report.html`, replacing only `<script>globalThis.__WEIV_PROPS__=…</script>` with the refreshed payload. `test/parity/test_performance_report.py` (9 tests) and `test/parity/test_promote.py` pass against the injected report. A diagnostic that names the failing emission step would remove the need for this workaround.

## Neiv frontend build inherits workspace TypeScript types (2026-11-10)

- **Classification:** Neiv tooling integration problem while building a Weiv desktop page; no confirmed Weiv compiler defect.
- **Task/context:** Build Harngine's `apps/coding-desktop` Neiv app, whose page is `web/App.weiv`. Neiv source commit `243b556`, package `0.1.2` (prepack reports `0.1.3`), Weiv checkout commit `1a33328`, `weivjs` dependency `0.1.2`, macOS arm64, Node `22.22.1`, TypeScript `5.9.3`.
- **Reproduction:** From `/Users/chao.yang/Private/harngine`, run `node /Users/chao.yang/Private/neiv/packages/neiv/bin/neiv.mjs build apps/coding-desktop`. The Harngine workspace has `@types/chai` and `@types/node` installed. Neiv's `packages/neiv/scripts/build-frontend.mjs` invokes `tsc` without a project file or explicit `--types`/module resolution.
- **Expected:** Neiv builds its frontend SDK and the app's Weiv page independently of the caller's unrelated ambient TypeScript types.
- **Actual:** Build exits 2 while compiling the Neiv frontend SDK: `node_modules/@types/chai/index.d.ts(2,58): error TS2792: Cannot find module 'assertion-error'`; `node_modules/@types/node/http.d.ts(2122,36)`, `(2126,37)`, `(2130,39)`, `web-globals/fetch.d.ts(3,25)`, and `worker_threads.d.ts(66,34)` each report `TS2792: Cannot find module 'undici-types'`.
- **Workaround:** Run `node packages/neiv/bin/neiv.mjs build /Users/chao.yang/Private/harngine/apps/coding-desktop` with cwd `/Users/chao.yang/Private/neiv`. That build succeeds and emits `build/NeivApp.app`; the Harngine launcher sets this cwd.

## Scoped `body` CSS leaves Neiv page colors unreadable (2026-11-10)

- **Classification:** Weiv scoped CSS behavior and documentation gap for document root selectors; confirmed in a Neiv WKWebView app.
- **Task/context:** Harngine `apps/coding-desktop/web/App.weiv` on macOS arm64, Neiv commit `243b556` (`neiv` package `0.1.2`, prepack `0.1.3`), Weiv checkout commit `1a33328`, `weivjs` `0.1.2`, Node `22.22.1`.
- **Reproduction:** Put `body { color: #e8e9e5; background: #101310; }` in a `.weiv` component's `<style>`, build it with `node packages/neiv/bin/neiv.mjs build /absolute/path/to/app`, and open the resulting Neiv app. The generated `styles.css` scopes the rule as `body[data-weiv-scope="..."]` and `[data-weiv-scope="..."] body`.
- **Expected:** The page body receives the intended dark background and light text, or the compiler warns that a component style cannot target the document body.
- **Actual:** The body remains white with default black text because the actual `<body>` is outside the component scope. Dark child cards then contain unreadable black text. No build diagnostic is emitted.
- **Workaround:** Put background, text color, and font on the component's root `<main>` and set `document.body.style.margin` and `document.body.style.backgroundColor` for the outer canvas. The rebuilt app screenshot showed readable colors.

## Deferred polling state in Neiv's Weiv 0.1.2 bundle (2026-11-10)

- **Classification:** released-runtime reactivity/documentation gap for the desktop integration; current Weiv source at `1a33328` documents managed deferred writes, while Neiv 0.1.3 depends on `weivjs` 0.1.2.
- **Context:** macOS arm64, Node 22.22.1, Neiv 0.1.3, Harngine Coding Desktop `App.weiv` in WKWebView. A long-running `async function monitorWork` awaited local HTTP calls in a `while` loop, then assigned scalar `workStatus` and array `interactions`.
- **Reproduce:** Start a writable coding Work that calls an approval-gated edit. After the Work reaches `waiting` and `GET /works/{id}` returns an approval interaction, observe the desktop panel. The server returns `waitingFor: "approval"` and the exact `interactions` array; the panel continues to show `Starting…` and no approval card.
- **Expected:** the waiting label and approval card update as the poll receives each snapshot.
- **Actual:** deferred assignments inside the never-ending async poll did not refresh those template regions. The generated `App.mjs` for this Neiv bundle provides `weivUpdate` through `__weiv_runBoundary`.
- **Workaround:** wrap the snapshot-driven assignments in `weivUpdate(() => { ... })`. The component builds with `node packages/neiv/bin/neiv.mjs build /Users/chao.yang/Private/harngine/apps/coding-desktop`. Runtime retest is pending.
- **Runtime retest:** with `weivUpdate` around the polling assignments, the same pending Work displayed `Waiting for approval`, the file path, removed and added text, and Approve/Deny buttons after the app relaunched. Approval then advanced the Work. This confirms the workaround in the Neiv 0.1.3 / `weivjs` 0.1.2 bundle.

## 2026-11-11: Type-only named import emits a runtime reference in a Neiv page

- **Classification:** Confirmed Weiv compiler defect.
- **Task/context:** Harngine coding desktop importing the reusable `neiv/http` client into `apps/coding/desktop/web/App.weiv`.
- **Versions/environment:** Neiv 0.1.3 declares `weivjs` 0.1.2; local Weiv checkout at commit `8bad2ad`; macOS 26.6.2 arm64; Node.js 22.22.1; TypeScript 5.9.3.
- **Reproduction:** In a `.weiv` script, write `import { localHttp, type LocalHttpEvent } from 'neiv/http';` and use `LocalHttpEvent` only in a TypeScript annotation. Build with `node packages/neiv/bin/neiv.mjs build <app>`. Inspect the emitted `App.mjs`.
- **Expected:** The type-only import is erased. The runtime imports and tracks only `localHttp`.
- **Actual:** The compiler emits `const LocalHttpEvent = __weiv_getTrackedRoot("LocalHttpEvent", __weiv_import_LocalHttpEvent);` but emits no definition or import for `__weiv_import_LocalHttpEvent`. The Neiv build succeeds, then the desktop page is blank at runtime. The build printed no error; a WebKit console error was not captured.
- **Workaround:** Import only `localHttp` and declare the event shape as a local `type` alias in the `.weiv` script.
- **Reproduction scope:** No credentials, tokens, or private workspace data are needed.
