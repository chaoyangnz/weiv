# Compiler Structure

The compiler is organized as explicit stages. Each stage owns the representation
it produces, following the same broad shape as the sibling Cyna compiler:

```text
source .weiv
  -> parser: SFC document + template AST
  -> project resolver + sema: SIR (ScriptFacts + TemplateBindings)
  -> lower: LIR
  -> ComponentUnit (owned compilation snapshot)
  -> backend/browser: RenderTree + BrowserComponent
  -> browser emit: JavaScript, scoped CSS, app bundles
```

## Stage Ownership

- `parser/` reads `.weiv` single-file components into the parser document model.
  The document has template, script, and style sections. Template syntax is
  parsed into `parser/template/ast.zig`; `parser/sfc.zig` owns the SFC document.
  Script and style remain raw
  section text at this layer so the parser owns structure, not TypeScript or CSS
  semantics.
- `sema/` turns raw script text into `ScriptFacts`, binds template references
  into `TemplateBindings`, and exposes those SIR model types from `sema/sir.zig`.
  `sema/bind.zig` implements binding; `sema/decode_script_facts.zig` decodes the
  FFI backend's JSON into semantic facts and transpiled script output. Script
  parsing is delegated through the FFI script backend; semantic model names
  should use `ScriptFacts`, not the older "script analysis" wording.
- `project/` resolves neighboring component information, including slot
  manifests, and follows imports/re-exports to establish managed shared-state
  ownership in `state_dependencies.zig`. `managed_state_plan.zig` owns the selection
  and subscription plan shared by that analysis and browser emission. The binder receives a manifest provider
  and does not open files. Template function construction and backend lowering
  failure diagnostics belong to their respective phases, not this resolver.
- `lower/` converts normalized template structure and bound expression
  references into LIR types in `lower/lir.zig`. LIR keeps expression source for
  code generation and an owned table of references for dependency analysis.
  `lower/template_functions.zig` constructs lexical function inputs from template
  expressions, script bindings, loop aliases and handler arguments, retaining
  generated-to-template ranges. Project dependency analysis, emission planning
  and failure diagnostics reuse it so they interpret the same lexical context.
  It constructs script-lowering inputs; it does not emit DOM operations or app
  artifacts. `lower/diagnostic_spans.zig` locates lowering failures; parser
  normalization uses its own `parser/template/diagnostic_spans.zig`.
- `component_unit.zig` owns `ComponentUnit` and `ComponentCompileReport`, the
  compilation snapshot and diagnostic report for one component. The unit owns
  a copy of the source buffer, parser, semantic, and LIR outputs, plus
  transpiled script JavaScript. The JavaScript is an output artifact, not a
  semantic fact. The parser, semantic, and LIR representations are target-neutral;
  the unit currently also carries the script backend's JavaScript output for
  browser emission. `ComponentCompileReport.takeUnit` transfers a complete unit
  and clears the report's ownership of its phase outputs.
- `backend/browser/render_tree/` lowers LIR into a browser `RenderTree`. Its
  `tree.zig` defines the representation and `lower.zig` constructs it. Its
  node arrays and effect arrays are owned, while source strings and attributes
  borrow from the unit's earlier representations. The tree must be destroyed
  before its unit. It is not a complete JavaScript module by itself.
- `backend/browser/component.zig` owns `BrowserComponent`, the browser-specific
  lowering result. It holds the `ComponentUnit` reference and render tree;
  generated source and CSS belong to emitters.
- `backend/browser/emit/` owns browser output. `js_module/` emits component JS,
  `scoped_css.zig` emits scoped CSS, and `app/` builds whole app bundles.
  `app/component_graph.zig` owns `ComponentGraph` collection, component registry
  validation and shared runtime copying; `app/module_graph.zig` plans and emits
  canonical JS/TS modules and component subscriptions from the managed state plan;
  `app/bundle_outputs.zig` emits the app entry and preview files;
  `app/runtime_imports.zig` classifies and rewrites runtime module imports;
  `emit/cell_diagnostics.zig` probes failed JavaScript cell lowering and reports
  emit-stage failures at original script/module/template locations. Both component
  and app emission use it; it does not resolve project ownership or change SIR.
  `app/preview_props.zig`
  infers demo props from the declared interface.
- `backend/browser/emit/js_module/` separates script setup, static runtime
  prelude, expression and component binding emission, structural helper
  emission, DOM creation, DOM updates, DOM destruction, and slot emission.
  `expressions.zig`, `components.zig`, `slots.zig` and `structures.zig` name the
  output responsibilities; `output.zig` holds JavaScript output primitives,
  `imports.zig` owns import selection/specifiers/declarations, and `slots.zig`
  also owns projected-slot object emission. `tracked_metadata.zig` serializes
  graph metadata into the generated module.
- `backend/browser/tracked_roots.zig` classifies browser-trackable bindings;
  `tracked_paths.zig` owns path discovery and ID assignment. Browser emission
  and graph inspection use the same table. These browser-specific files do
  not belong to target-neutral `sema/`.
- `backend/browser/dependencies.zig` analyzes the static dependencies used by
  runtime update guards. It reads LIR expression references for template
  expressions and scans helper bodies that are not part of template binding.
  `backend/browser/region_graph.zig` combines these dependencies with tracked
  paths and owns runtime region IDs. Build this graph
  once per browser module, then pass it to the metadata and DOM emitters.
- `compile.zig` is the compile-unit coordinator for one `.weiv` component. It
  runs a single report-producing stage sequence. `compile` takes a complete
  unit from that report and preserves the original stage error on failure.
  The coordinator does not own AST, SIR, LIR, render-tree, or emit rules.
- `inspect/` formats stage representations and derived debug views for CLI
  `emit` output. Its invalidation view uses the browser region graph, path
  table, and dependency analyzer. It adds explanatory nodes and warnings but
  does not assign a second set of path IDs. It is a formatter layer, not a
  compiler stage.
- `diagnostics.zig` contains shared diagnostic types and formatting helpers.

Keep new compiler code inside the phase that owns the data it creates. One-file
component orchestration belongs in `compile.zig`; target-specific output belongs
under `backend/<target>/`; representation formatters belong in `inspect/`. If
code does not clearly belong to a phase, target, compile-unit coordinator, or
formatter, keep it at the top level of `compiler/`.

## File Naming

Use lower snake case. Name a module for its operation or representation within
its owning directory:

- Pass implementations use verbs: `parse.zig`, `normalize.zig`, `bind.zig` and
  `lower.zig`. Directory facades expose operations through `index.zig` without
  exporting redundant parser/binder/lowerer implementation aliases.
- Representation files use domain names: `ast.zig`, `sir.zig`, `lir.zig`,
  `tree.zig` and `managed_state_plan.zig`. `parser/sfc.zig` remains the compact
  SFC model/parser; the redundant parser AST re-export file is removed.
- JavaScript emitter helpers use responsibility names inside `emit/js_module/`,
  rather than repeating a `_codegen` suffix. Output primitives, import handling
  and slot construction have separate owners instead of a `common.zig` bucket.
- Name source scanning and error lookup explicitly: `scan.zig` and
  `diagnostic_spans.zig`. Use `inspect/` for representation formatting.

The sibling [compiler architecture](../../../weiv-arch/docs/compiler-architecture.md)
and [structure audit](../../../weiv-arch/docs/compiler-structure-audit.md) record
the navigation map and canonical old-to-new file names.

## Reactivity Ownership

- `sema/` identifies script bindings, template references, mutations, and
  callback ownership. It reports cases that cannot be tracked precisely.
  Managed writes notify independently of the callback that performs them.
  Unsupported ownership/effect cases retain explicit boundary diagnostics.
- `lower/` preserves bound template references in LIR. Script state and callback
  facts remain in the unit for backend analysis.
- `backend/browser/` decides which DOM regions depend on those values and
  emits their update operations. Browser-specific proxy and scheduler code
  belongs here, not in semantic analysis. Managed state writes are immediate;
  dependent DOM updates are batched into microtasks. Callback wrappers and the
  injected `weivUpdate` helper have been removed.
- `packages/weiv/src/runtime/observable.ts` provides explicitly shared state.
  Its public `observable` and `subscribe` API supplies an explicit external-state
  boundary over the same reactive core used by managed local/shared state.
  Generated browser modules bridge imported observables
  into selective updates by their imported binding names. Aliases of the same
  observable share one listener and invalidate each matching binding name.
- `inspect/invalidation_graph.zig` explains the analyzed graph. Its
  `runtime-regions` section reads the same browser graph as code generation.
  Its existing `regions` section also displays nested explanatory nodes that
  are not independent runtime update regions. Keep that distinction explicit.

Imported observable notifications include changed property paths. Direct member
expressions such as `shared.count` use those paths to select individual regions.
Expressions involving calls or operators keep the imported-binding fallback.
Compiler-tracked local paths also select individual nested paths.

## CLI Stage Output

The CLI can emit major stage representations to stdout or to an optional file:

```bash
weiv emit ast <path> [out-file]
weiv emit sir <path> [out-file]
weiv emit lir <path> [out-file]
weiv emit render-tree <path> [out-file]
weiv emit invalidation-graph <path> [out-file]
weiv emit js <path> [out-file]
weiv emit css <path> [out-file]
```

Use `compile` for a whole app bundle:

```bash
weiv compile <root.weiv> [out-dir]
```

The default app output directory is `dist`.

## Naming Rules

- Use `parser`, `sema`, `lower`, and `backend` for compiler stage names.
- Use `SFC document`, `template AST`, `ScriptFacts`, `TemplateBindings`, `SIR`,
  `LIR`, `ComponentUnit`, `RenderTree`, and `BrowserComponent` for the major
  representations.
- Prefer `render-tree` over the older `browser-plan` wording.
- Prefer `lir` over the older generic `ir` wording.
- Prefer `script_backend` for the Zig FFI wrapper. The native Rust library is
  still named `weiv_parser_backend` until the Rust crate is renamed separately.
- Use `ComponentGraph` for the app's component graph. Its nodes are components; it
  also tracks runtime imports copied into the bundle. Use
  `region_graph.Graph` for DOM update regions. `tracked_metadata` names
  serialization; it does not build the graph.
- A `BrowserComponent` is a lowered browser component, not an emitted module.
  Keep source strings and CSS out of that struct.
- SIR is the semantic pair of `ScriptFacts` and `TemplateBindings`. There is no
  separate `SirDocument` allocation or ownership layer.
- `ComponentUnit` names the owned compilation snapshot, not another IR stage.

## State contract reference

Current author-facing guarantees are in
[the package README](../../packages/weiv/README.md#state-contract-managed-reactivity-by-default).
The state semantics, ownership decision, acceptance criteria, and next
steps live in the sibling architecture repository:
[Predictable Component State Contract](../../../weiv-arch/docs/component-state-contract.md).

The default `emit js` path uses original-script lexical lowering in
`libs/parser-backend/src/cells.rs` and the common runtime cell scope. `emit app`
and the Vite/Bun plugins manage the reachable component/module graph together,
preserving canonical identity and live exports. Legacy selection, alternate
`js-cells`/`app-cells` commands, and their separate implementation have been removed.

The internal `emit managed-project <manifest.json> <out-dir>` command accepts a
project root and component roots and writes canonical module/source mappings for
bundlers. Original JS/TS consumers are redirected to those same emitted modules.
`--runtime-dir` selects matching source or packaged runtime files independently
of the caller's working directory. Boundary warnings support JSON diagnostics.
Standalone component output manages locals but cannot claim imported-module
ownership without the managed graph. The bounded contract and retirement plan
live in weiv-arch; no universal JavaScript effect inference is implied.
