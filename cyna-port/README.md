# Weiv in Cyna

The Cyna compiler is the source checkout CLI and Darwin arm64 package binary.
The Rust script backend and JavaScript runtime remain part of the compiler.
Other packaged native targets await Cyna toolchain artifacts. The exercised
inspection, validation, diagnostic and output-file matrix matches the preserved
Zig CLI. Generated JavaScript and CSS use semantic and runtime equivalence as
their release gate.

## Run

Verified host: macOS arm64, Cyna 0.5.0 with its installed runtime/LLVM, and
Cargo 1.99.0. From the Weiv repository root, build the release CLI and Darwin
arm64 platform package binary together:

```sh
npm run build:cyna
```

Then run the native Cyna workflow (no Python or Zig needed):

```sh
SDKROOT="$(xcrun --show-sdk-path)" cyna build cyna-port/cyna.release.toml --output /tmp/weiv-cyna-release
cyna check cyna-port
cyna test cyna-port
cyna run cyna-port -- --runtime-dir packages/weiv/dist/runtime emit app test/examples/slots/CardUsage.weiv /tmp/weiv-browser-output
cyna run cyna-port -- emit js test/examples/slots/CardUsage.weiv > /tmp/CardUsage.mjs
cyna run cyna-port -- emit css test/examples/slots/CardUsage.weiv > /tmp/styles.css
cyna run cyna-port -- emit-module-cells cyna-port/fixtures/managed-state/state.ts ./state.publisher.mjs '["count","other"]' > /tmp/state.mjs
cyna fmt cyna-port/src --check
```

Set `CYNA` to the current compiler binary if needed; on macOS the build script
supplies `SDKROOT` from `xcrun` automatically. It builds the retained Rust
backend with locked dependencies, writes `zig-out/bin/weiv` for the source
checkout, and copies the same binary into the Darwin arm64 platform package.
The Darwin arm64 release artifact is 11 MiB versus 22 MiB for the preserved
Zig artifact.

`emit app` (and `compile emit app`) follows relative `.weiv` component imports
and writes one `.mjs` file per component, follows relative `.js`, `.mjs`, `.ts`,
and `.mts` module imports (including transitive imports), transpiles TypeScript
modules through the retained Rust backend, and writes `styles.css`. Pass a
runtime directory with `--runtime-dir` to copy the six browser runtime files
under `__weiv_runtime` and rewrite virtual imports to relative paths. Build that
directory with `npm run build --prefix packages/weiv` when needed. Omitting the
runtime directory keeps virtual imports for a bundler. The project builder
currently uses local state dependencies. For directly imported named exports
written at module scope, it also emits a publisher companion and subscribes the
component to that publisher. Local export aliases, named import aliases, and
chains of named reexports, including unambiguous star exports, resolve to the
source binding and its publisher file. Ambiguous writable star exports fail the
project build. Namespace access, transitive publisher ownership beyond this
resolution, package imports, and automatic runtime preparation remain open. The
package source path now selects a Cyna release binary; non-Darwin-arm64 package
targets remain blocked by Cyna's available target and standard-library artifacts.

`dev <entry.weiv> [out-dir]` writes the same preview app and starts Bun's hot
development server. It prints Zig-shaped session, file-watch, rebuild and
rebuild-complete messages, and rebuilds through `emit app` when a source file
changes.

`build-browser` and `inspect-project` are compatibility spellings rather than
supported CLI operations: the preserved Zig binary does not expose either
command, so the Cyna binary prints the same usage text and exits successfully.
Use `emit app` for project output and the supported inspection commands below.

`inspect-lir <entry.weiv>` prints the target-neutral LIR in the Zig reference
format, including imported component slot manifests. It reads source files and
does not write output files. The Card and CardUsage fixtures match the Zig
inspector text exactly. `inspect-render-tree <entry.weiv>` (also
`inspect-browser-plan`) formats the browser render tree with reference IDs and
structural anchors. Card, CardUsage, conditional-toggle, and todo-list match
the Zig inspector output.

`inspect invalidation-graph <entry.weiv>` also accepts
`inspect-invalidation-graph`, `dump-invalidation-graph`,
`emit invalidation-graph`, and `compile emit invalidation-graph`, with an
optional output file for emit forms. The formatter matched Zig byte for byte
across 19 inline reference fixtures and the basic-counter, TodoMVC, Kanib app,
and Kanib issue-board components.

The optional structural comparison mode,
`python3 tools/test-cyna-javascript.py --flat --structural`, reports exact,
byte-mismatched and still-rejected emitted modules against the Zig reference and
can be narrowed with `WEIV_CYNA_CASE=<path>`. Byte identity is no longer a
release requirement for generated JavaScript or CSS. Harmless differences such
as path-derived scope IDs or subscription registration order are accepted when
exports, DOM behavior, update scheduling, and CSS scope wiring are equivalent.
Exact bytes remain required for text inspection formats and other public byte
contracts.

`emit-js <entry.weiv>` writes the entry component's generated JavaScript module
to standard output. It uses the same in-memory project build as `emit app`,
including local module and managed-state selection, and writes no project files.
The Zig-compatible `emit js` spelling is preferred. The command is useful for
direct compiler comparisons; imported modules still require `emit app`.
`emit-css <entry.weiv>` prints the project stylesheet assembled from the
entry component and its imported components, matching `emit app`'s
`styles.css` output.
`emit-module-cells <module> <companion-import> <bindings-json>` lowers a
JavaScript or TypeScript module through the retained Rust backend and prints
the resulting module. The bindings argument is a JSON array of mutable export
names. The Zig-compatible `emit module-cells` spelling is also accepted. A
focused managed-state fixture matches Zig's `emit module-cells`
output byte for byte.

The standalone Cyna binary also accepts `analyze module-state <module>`,
`emit js <entry.weiv>`, `emit css <entry.weiv>`, and `--help`. With
the package source resolver selecting a `cyna build cyna-port` output, the
complete current `test/package/*.test.mjs` suite passes, including module cells,
managed state, diagnostics, helper bindings and Vite/Bun execution.
`compile emit app <entry.weiv> <out-dir>` and
`emit app <entry.weiv> <out-dir>` write a preview app with its runtime. The
local package E2E test passes when `WEIVJS_PACKAGE_SPEC` points to this
checkout and the source runtime directory has been prepared, or the package
runtime fallback resolves the built files. Preview props are inferred from the
root component's typed `Props` interface, and the preview server includes Zig's
package-bundling route.

`tools/test-cyna-project.py` executes the repository's imported observable
fixture and the direct managed state fixture in Bun/jsdom. It checks that events
update the displayed values after the reactive scheduler flushes.

The permanent `src/sfc_reference.test.cy` suite contains 112 SFC cases: 35 targeted
boundary/error inputs and 77 component inputs captured from the Zig reference.
Inputs and expected results are stored in ordinary Cyna source. Tests run
without Python, Zig, or generation, using the project command above. They check
exact errors, style presence, and every section range. New regression tests can
be written directly in Cyna.

## Optional migration comparison

To compare the current Cyna implementation with the live Zig parser and current
tracked `.weiv` files, install Python 3 and Zig 0.17.0, then run:

```sh
python3 tools/test-cyna-sfc.py
python3 tools/test-cyna-template.py
python3 tools/test-cyna-normalize.py
python3 tools/test-cyna-script-facts.py
python3 tools/test-cyna-slot-manifest.py
python3 tools/test-cyna-binding.py
python3 tools/test-cyna-lowering.py
python3 tools/test-cyna-lowering.py --coordinator
python3 tools/test-cyna-lowering.py --render-tree
python3 tools/test-cyna-template-functions.py
python3 tools/test-cyna-tracked-paths.py
python3 tools/test-cyna-dependencies.py
python3 tools/test-cyna-regions.py
python3 tools/test-cyna-css.py
python3 tools/test-cyna-javascript.py
python3 tools/test-cyna-javascript.py --flat
python3 tools/test-cyna-project.py
```

These optional tools generate temporary assertions and invoke `cyna test`; they
never change the permanent tests by default. The template comparison checks
preorder structure, spans, attribute/directive content and metadata, slot names,
and exact errors across the current component corpus. To explicitly refresh their reference inputs and
expectations after a deliberate compatibility change:

```sh
python3 tools/test-cyna-sfc.py --update-reference-tests
cyna fmt cyna-port/src/sfc_reference.test.cy
```

Review the resulting changes before accepting a new baseline. Handwritten
regressions belong in a separate `.test.cy` file so refreshes cannot overwrite
them. A newly added or modified repository fixture is picked up by the optional
comparison immediately; it enters the permanent reference suite only on refresh.

`CYNA` and `ZIG` may select alternate compiler executable paths for the comparison.
Prefer absolute paths. Temporary sources are removed even on failure. The
SFC/template-only comparisons need no Rust build; script/frontend/module
comparisons use the retained Rust archive built above.

## Template parser

`src/compiler/parser/template/parse.cy` exposes `parse([]const u8)`.
The handwritten `src/template_static.test.cy` and `src/template_dynamic.test.cy`
tests run through the same
`cyna test cyna-port` command. They cover static nested trees, text and whitespace,
UTF-8 byte spans, ordinary attributes, self-closing/HTML void tags, malformed
markup, SFC handoff, and 2,048 levels of nesting.

The returned document owns flat preorder node and attribute lists. Element nodes
reference their attributes by start/count; `subtree_end` skips a whole subtree.
Enumerate roots starting at zero, or children starting at the parent's ID plus
one, and advance to each node's `subtree_end`. Source spans are relative to the
input template slice. The caller retains that slice's immutable source snapshot;
add its SFC content offset when mapping template spans back to the full file.

Interpolation, `#if`/`#else`/`#for`, canonical and legacy events/bindings,
slot assignment, and slot outlets with fallback children are supported.
Expressions remain byte spans; parsing does not evaluate or semantically validate
TypeScript. Directives occupy their own document-owned list, with ranges on
elements. Slot outlets retain their original attribute ranges for inspection.
Every directive has a full source span. Errors are imported directly from
`compiler.parser.template.errors`.

Double-quote handling, interpolation's first `}}` delimiter, legacy empty target
quirks, and closing-tag boundaries follow the Zig reference. Slot constraints
are checked after child parsing, while directive splitting precedes children.
Only successful parses expose an AST; failures return no partial document.
Semantic binding, target-neutral lowering, browser planning and static module emission are implemented below.

An optional Zig-only contract suite verifies the same static expectations against
the unchanged reference parser, with no Python involved:

```sh
zig test --dep parser -Mroot=cyna-port/reference/template_static.zig -Mparser=src/compiler/parser/index.zig
zig test --dep parser -Mroot=cyna-port/reference/template_dynamic.zig -Mparser=src/compiler/parser/index.zig
zig test --dep parser -Mroot=cyna-port/reference/template_normalize.zig -Mparser=src/compiler/parser/index.zig
```

## Template normalization

`src/compiler/parser/template/normalize.cy` exposes
`normalize(&const TemplateDocument): NormalizedDocument!NormalizeError`.
The handwritten `src/template_normalize.test.cy` suite runs with the other tests
through `cyna test cyna-port`, including 1,024 nested conditional wrappers.

The output is a separate preorder arena. Element payloads identify the raw node
and a range of kept directive IDs; attributes and source data are read through
the associated raw document. Slot outlets similarly retain raw node identity.
Keep the raw document and its source snapshot available while consuming this
output. IDs are local to that raw document, not portable handles or references
to a different parse. Normalization does not modify it and may run repeatedly.

Conditional and loop wrappers have explicit subtree ranges. Conditional
consequents begin at the wrapper ID plus one and end at `alternate_start`;
alternates end at `subtree_end`. When no else exists, those two end indices are
equal. Loop bodies, element children, and slot fallback use ordinary preorder
child traversal. Conditional spans cover the original if element, not the
consumed else sibling.

Zig's directive precedence and structural filtering are preserved. Real text or
interpolation interrupts else adjacency; whitespace-only text is already omitted
by parsing. An unpaired else produces `NormalizeError.unexpected_else`. Runtime
event/binding/slot-assignment directives remain in order; structural directives
are replaced by wrappers and removed from plain elements. Script expressions
are still opaque source spans.

The optional normalization comparison checks the current tracked component
corpus plus targeted precedence/error inputs against Zig. It checks normalized
node kinds, subtree/branch boundaries, source spans, runtime directives and exact
parse/normalization errors. It leaves permanent native tests untouched.

## Rust script-backend adapter

`src/ffi/script_backend.cy` exposes
`analyze_raw(source: string, source_path: string): string!ScriptBackendError`.
The result is an owned Cyna JSON string. Rust's `ok=false` syntax diagnostics are
returned normally; transport failures use typed errors. Successful Rust parsing
can still include component diagnostics (for example, missing props declarations),
so later semantic decoding must preserve both `ok` and diagnostics independently.

Both inputs reject embedded NUL instead of silently truncating. The adapter owns
and frees temporary input buffers, copies the output before freeing it with
Rust's own function, and retains no foreign pointers in its public result.
`src/ffi/script_backend.test.cy` uses Cyna's friend-test support to check the
private null-response boundary without exposing raw addresses as public API.

A small companion C bridge works around Cyna LG-55: nullable C pointer returns
currently use the wrong ABI. It carries pointer addresses as integers across
the C boundary and maps zero to failure before any dereference. It does not
analyze scripts or decode JSON. The original Rust ABI is unchanged. Existing
LG-36 and new LG-54 explain the explicit buffer construction instead of a scoped
standard-library C-string helper. The workaround is verified only on macOS arm64.

Use project commands (`cyna test cyna-port`, `cyna run cyna-port`) to retain the
manifest's C companion and native link settings. A single-file build/run does
not load those project link settings. Optional migration tools also invoke the
project test command, with their temporary test root discovered automatically.
Tests never build the Rust archive implicitly. The full compiler CLI is still
pending; typed decoding is implemented as the independent stage described below.

## Typed script facts

`src/compiler/sema/decode_script_facts.cy` exposes
`decode(source: string): DecodedScript!ScriptDecodeError`. Pass the owned JSON
returned by `analyze_raw` to this stage. The result model is defined in `compiler/sema/decoded_script.cy`.
`DecodedScript.facts` contains props,
imports, bindings, diagnostics and all state helpers/mutations/aliases/callbacks;
`DecodedScript.transpiled_code` is a separate JavaScript output artifact.

Returned records own their lists and retain their immutable Cyna strings. They
remain valid after the temporary JSON tree and input string go away. Source
ranges use shared `Span` values; diagnostic line/column fields are checked u32
values. Kind/severity/reason labels remain strings for protocol compatibility.

Unknown fields are ignored. Nullable top-level and record members remain
required; JSON null preserves absence. A null state or missing individual state
collections produces empty lists, while explicitly null collections are invalid.
Malformed JSON, missing fields, wrong shapes, integer overflow and inverted
ranges return typed errors from `compiler.sema.script_json`.

Unsigned values must be canonical nonnegative JSON integer tokens. Numeric
strings, floats and exponents are rejected even where Zig's general JSON library
coerces them. Inverted ranges are rejected as well. These are documented internal
protocol validation changes; the Rust backend emits canonical ordered values.
Cyna's JSON parser also rejects duplicate keys. Valid backend responses retain
all facts and ordering, including diagnostics present with `ok=true`.

The permanent `src/script_decode.test.cy` suite contains malformed-payload,
complete-record, ownership-lifetime and actual Rust-response cases. It uses
fixture functions rather than top-level string constants for installed Cyna
LG-56 compatibility. No test generation is needed for everyday testing.

The optional script-fact comparison checks every decoded field and emitted
JavaScript against Zig for all tracked components, and includes Zig schema
contracts from `reference/script_decode.zig`. It batches eight components per
temporary root with four native workers; `--batch-size` and `--jobs` can tune
that optional workload (Cyna LG-57 tracks single-root compile cost). It calls the retained Rust ABI
directly using current Zig's `dupeSentinel` API: the existing production Zig FFI
wrapper uses removed `dupeZ` and is not modified by this port.

## Slot manifests

`compiler/sema/slot_manifest.cy` defines the manifest/report model and pure
`has_default` / `has_name` queries. `compiler/sema/build_slot_manifest.cy` exposes
`build(source, &raw, &normalized)`: give it template-relative bytes and the paired
raw/normalized documents. It returns detached name strings, every outlet entry
and one duplicate report for each later occurrence. Default slots and explicitly
empty names remain distinct. Callers can retain the manifest after source and
parser models go away; source spans keep their original diagnostic coordinates.

Discovery walks both conditional branches and loop bodies statically. Outlets
inside another outlet's fallback are excluded, matching Zig. Projection directives
such as `slot:header` do not declare outlets. Duplicate reports are data for later
binding diagnostics, rather than build failures. Input ASTs remain unchanged.

The permanent `src/slot_manifest.test.cy` tests cover ordering/spans, duplicates,
lookup behavior, empty/default names, nesting/fallback and detached Unicode names.
Read-only lookups use explicit indexed borrows for Cyna LG-58 compatibility.
Imported manifest resolution remains in the future project layer; template
binding consumes explicitly supplied manifests as described below.

## Template binding

`compiler/sema/template_bindings.cy` owns bound component/expression facts,
diagnostics and the own-slot manifest. `compiler/sema/bind_template.cy` exposes
`bind(source, &raw, &normalized, &script, &catalogs)`. The imported slot catalog
model is `component_manifests.cy`; it is supplied before binding and requires no
filesystem access. An absent child manifest skips cross-component slot checks
while lexical component resolution still runs independently.

`bind_expression.cy` handles lexical references and helper warnings;
`binding_context.cy` shares pass-private scopes and diagnostic construction.
Expression source ranges pair with the template; returned names/text/containers
are owned independently. Diagnostic BindingSource identifies template vs script
coordinates, including reserved emit-binding ranges. Loop scopes are iterative and expire at subtree boundaries.
The binder preserves Zig reference order, call upgrades, warnings and diagnostic
ordering/messages/severity, including its existing identifier-location arithmetic.

The handwritten `template_bind.test.cy` suite covers hidden/visible/component
names, quotes/properties/spreads/template strings, loop shadowing and expiry,
builtin/reserved emit, helper warnings, deprecated/Vue-like directives, named and
default content, duplicate grouping and fallback. It also checks repeated pure
binding and 256 nested loop scopes. Optional live parity checks all 77 components
with an empty imported catalog plus targeted nonempty-catalog cases against Zig.

## Current API

`src/compiler/parser/sfc/parse.cy` accepts an immutable `[]const u8` and returns a
`SfcDocument!ParseError`. The model lives in `parser/sfc/ast.cy`. Sections contain byte spans, including tag and attribute
ranges, rather than duplicated text or borrowed fields. The caller supplies and
retains the associated immutable source snapshot. A document must only be used
with that snapshot; source IDs will be added when multi-source compilation needs
them. UTF-8 offsets are bytes, not characters or editor coordinates.

Use explicit type imports for public enums, for example:

```cyna
import { parse, ParseError } from .compiler.parser.sfc.parse;
import { SfcDocument, SfcSection } from .compiler.parser.sfc.ast;
```

Current error names correspond to the Zig error set in snake case. There is no
parser allocation, so Zig's allocator-only `OutOfMemory` case is not part of this
API. Human diagnostic formatting and error locations are deferred; the reference
SFC diagnostics currently have no source span either.

See [model/operation boundaries](docs/ARCHITECTURE.md),
[architecture decisions](docs/DECISIONS.md) and [port progress](docs/PORT_PLAN.md).
Cyna capability reports live only in the sibling Cyna
[`LANGUAGE_GAPS.md`](../../cyna/docs/LANGUAGE_GAPS.md).

## Template lowering

`compiler/lower/lir.cy` defines the persistent target-neutral model;
`compiler/lower/lower_template.cy` operates on source, paired raw/normalized
models and bound expression facts. LIR owns a flat node arena and explicit
root/child IDs, avoiding recursive storage and drop. Spans need the retained
source only; expression references are copied into independent owned lists.

Components group default/named slot provisions in first-encounter order, merge
interleaved children and flatten named template groups. HTML attributes and
event/bind effect order match Zig; ordinary component attributes are discarded.
Invalid slot/template placement remains a typed hard lowering error. Expression
lookup uses source-range identity rather than text equality.

Fourteen handwritten native tests cover these contracts, structural wrappers,
reference ownership and 512 nested elements. The optional live comparison walks
logical child edges and checks complete output against Zig for all tracked
components plus targeted cases. It does not replace the native suite.

## In-memory component compilation

`compiler/compile.cy` composes SFC/template parsing, normalization, live Rust
analysis, typed decoding, binding and LIR lowering. `compile_report` accepts
source/path strings and an immutable manifest catalog; it returns the
`component_unit.cy` partial report, retaining all completed stages on failure.
No filesystem resolution is implicit. `take_unit` transfers a complete set of
owning stage results exactly once; the report retains diagnostic/source context.
The complete unit owns source, section spans, raw/normalized templates,
DecodedScript facts/artifact, bindings and LIR.

`diagnostics.cy` records typed stages and explicit file/template/script origins.
`map_diagnostic_span.cy` converts valid fragment ranges into full-file byte
ranges. Stage errors retain exact codes and absent locations when the pass
provides no span. CLI wording, line/column presentation and precise parser/
lowering diagnostic searches remain later work. Existing binding diagnostics
retain their numeric offsets; the coordinator makes their source origin clear.

The `--coordinator` comparison mode compiles the live input through the Rust
backend and coordinator, checks LIR against Zig through logical edges and checks
hard failure stages/codes. Permanent ownership/failure/mapping regressions run
with `cyna test cyna-port` without Python or Zig.

## Template-function inputs and generation

`lower/template_functions.cy` owns lexical inputs, generated code and expression
range mappings. `collect_template_functions.cy` captures exact expression spans,
script names, loop locals and event/payload argument names from the paired raw/
normalized models. Inputs own their name lists independently of earlier stages.
`build_template_functions.cy` validates and selects expressions with the Rust
backend, then generates shared evaluator wrappers. It supports mutation-only or
all-supported-expression selection and copies a caller-supplied prefix without adding an
array suffix. Its `append` primitive is available to later runtime planning.

Source mappings use exact parser ranges, correcting the Zig collector's earlier
substring-match ambiguity. The optional comparison checks generated bytes and
ranges against Zig, and template ranges against an independent pointer-offset
oracle. Sixteen native tests cover scope/handler semantics, prefix offsets,
filtering, invalid JSON, embedded NUL and 256 nested loop scopes.

## Browser render tree

`backend/browser/render_tree/tree.cy` defines browser nodes and reference IDs;
`lower.cy` converts valid LIR into an independently owned browser tree. Flat
node IDs correspond to LIR IDs, while logical child/provision edges determine
reference allocation. Elements and components allocate references after their
children; structural nodes allocate anchors/state/handles first. Event and bind
effects are partitioned stably. Attribute, effect and child/provision collections
survive destruction or replacement of the original LIR owners.

Twelve native regressions cover exact allocation order, projected-slot merging,
attributes/effects, ownership and 512 nested elements. The optional `--render-tree`
mode runs the full coordinator and compares every browser payload/reference with
the actual Zig renderer. Tracked state and region analysis are separate operations
described below; DOM/JavaScript emission remains pending.

## Tracked roots and canonical paths

`backend/browser/tracked_roots.cy` and `tracked_paths.cy` own typed root records,
canonical path strings, stable one-based IDs and parent links.
`classify_tracked_roots.cy` reads script facts to classify imported, props and
eligible local roots. `collect_tracked_paths.cy` reads a template expression
range and script/LIR facts, then appends paths and unique leaf IDs to explicit
caller-owned collections. Source coordinates must match the LIR snapshot;
collection order controls stable IDs. Finished tables retain no component,
script, LIR or temporary canonical-buffer dependency.

Sixteen native regressions cover classification precedence/exclusions, canonical
prefixes and IDs, source-identity filtering, scanner edge cases, independent
ownership and 256-segment chains. The optional live comparison checks full
classification/path outputs against Zig. Legacy quoted/commented path false
positives are documented in WEIV_FRICTION.md and preserved pending a separate
precision change. Dependency closure and region allocation are separate passes
described below.

## Dependency analysis

`backend/browser/dependencies.cy` owns ordered dependency names;
`collect_dependencies.cy` handles expressions, helper closure, browser subtrees
and explicit visible-binding filtering. Callers supply immutable script/LIR
facts, source ranges, loop locals and an imported-call policy. Bound references
preserve their order/call flags; absent ranges use the reference fallback
scanner. Helper reads precede depth-first calls, with path-local cycle protection.
Both helper expansion and subtree traversal use explicit work stacks.

HTML event handlers are excluded from update dependencies; component events,
binds, projected content, structural expressions and slot fallback are included.
Filtering to visible bindings is separate and stable. Nineteen native tests cover
these contracts, ownership, cycles, name-resolution quirks and 256-deep helper/
loop traversals. The optional comparison checks both imported-call policies and
before/after filtering; `--targeted-only` runs focused cases without the corpus.
The shadowed-script-helper precision gap is documented in WEIV_FRICTION.md.
Region planning composes these operations as described below.

## Region planning

`backend/browser/region_graph.cy` owns typed regions and their shared tracked-path
inventory; `build_region_graph.cy` composes the render tree with dependency/path
analysis. Region IDs follow encounter order and retain the browser reference IDs.
Added render-node IDs and source spans provide explicit provenance. All names,
arrays and path records survive destruction of the input models.

Ordinary elements contribute bind regions before child text regions. Each
conditional, loop, component or slot outlet owns one subtree region, with full
descendant dependency closure. Header/direct-effect paths are collected according
to the reference rules; nested regions are not duplicated. Exact imported-path
expressions receive the same precise import hint as Zig. Region construction is
iterative and retains imported calls explicitly.

Sixteen native tests cover IDs, ordering, hints, structural/path boundaries,
ownership, constant expressions and deep trees. The optional region comparison
checks complete graphs and added provenance against the live Zig pipeline.
Browser component assembly and scoped CSS emission are implemented below;
JavaScript/DOM emission remains pending.

## Browser assembly and scoped CSS

`backend/browser/component.cy` owns the complete compilation unit, render tree
and region graph. `build_component.cy` consumes a unit and constructs that
browser snapshot; source-backed spans keep their context without an external
unit pointer or destruction-order requirement.

`compute_scope_id.cy` computes the reference-compatible `w` plus sixteen
uppercase hex digits from exact path bytes. It ports Zig's Wyhash calculation
in Cyna with explicit integer loads/limb products. Paths are not normalized.
`emit/emit_scoped_css.cy` returns an owned stylesheet independently of browser
planning. It preserves selector rewriting, globals and at-rule behavior, using
an explicit stack for nested recognized groups. `append_diagnostics` reports
unterminated rules with the exact fatal emit code/message and full-file style
range; frontend compilation and browser construction remain inspectable.

Seventeen native tests cover hash goldens, ownership, CSS behavior, diagnostics
and 256 nested groups. The optional CSS comparison checks all components,
focused styles and hash-boundary paths against Zig. Known container/comment/
at-rule-prefix limitations are recorded in WEIV_FRICTION.md and preserved for
compatibility. Static JavaScript/DOM emission is implemented below; dynamic
emission and full diagnostic presentation remain pending.


## Static JavaScript modules

`emit/javascript_module.cy` contains only `ImportOverride` and the owned
`JavaScriptModule { code, scope_id, css }` artifact. The separate
`emit/emit_static_module.cy` operation reads a BrowserComponent and import
mappings, rejects dynamic templates, and emits a complete ES module. There is
no project filesystem lookup or implicit managed-cell selection. This API
matches the reference's explicit empty cell/local subscription selection.

Shared `emit/js_module/` operations handle JavaScript strings, HTML entities,
imports, Rust cell-lowering response validation and tracked-state metadata.
Static DOM creation uses an explicit work stack, scope markers and SVG/
foreignObject namespace handling. Setup and lifecycle/mount exports use the
retained real Rust backend and existing JavaScript cell runtime. Immutable
reference fragments and all 2,125 named entities are ordinary Cyna source;
Python is not part of compilation or permanent tests.

`javascript.test.cy` covers the public slice and transport boundaries. Optional
`tools/test-cyna-javascript.py` checks import/metadata semantics across the
corpus, generated module structure, complete module availability and entity
decoding against actual Zig. Its runtime checks additionally require Bun and
jsdom and execute native Cyna output with the real cell runtime. Generated
module bytes may differ when exports and behavior are equivalent. The static-only
entry point returns `unsupported_template` for interpolation, binds/events,
conditionals, loops, child components and slot outlets. The general module entry
point below also supports interpolation, binds, element events, conditionals and
keyed loops with fixed DOM bodies. Script behavior follows the explicit
empty-selection API; full project/managed-state analysis is pending.


## Evaluator planning and dynamic updates

`emit/evaluator_plan.cy` owns typed evaluator IDs, site/argument kinds and exact
template/generated ranges. `build_evaluator_plan.cy` reads the render forest,
source and script facts, validates expressions through Rust, and builds detached
lexical closures in logical order. It supports planning conditionals, loops,
components/projections and fallback content already, with an explicit scope-task
stack. It leaves render expressions and dependency regions unchanged. This
replaces the reference's hidden NUL marker strings with a typed side table.

`emit/emit_module.cy` emits browser modules for nested elements, static text,
interpolation, bindings, element events, conditionals and keyed loops. Shared
`js_module/emit_setup`, `emit_dom`, `emit_updates`, `emit_binding_update` and
`emit_evaluator_call` operations keep setup, creation, full/selective updates,
binding rules and evaluator calls separate. The static-only entry point now
validates its stricter input and delegates to the same module operation.

Bindings preserve class/static merging, checked/disabled/selected properties and
attributes, value property/attribute synchronization, style, aria and general
attribute behavior. Events refresh instance scope and execute normalized lexical
handlers. Original region/path metadata drives selective updates; a mismatched
region graph returns a typed error rather than routing an incorrect update.

This API still passes explicit empty managed-cell/local subscription selections
to Rust. Props updates are watched and event dispatch works. Template assignments
to unselected script locals return
`cell_template_untracked_assignment_unsupported`; automatic script-cell selection
and managed imports remain future work. Imported child components without
projected slots mount through boundary handles and receive prop/callback updates.
Slot outlets support fallback and supplied handles. Nested structures within a
branch, loop, slot fallback or projected slot still return
`unsupported_template` at module emission. Fixed DOM projected default and
named slots are supported.
Callers can now use `emit_with_selection` with explicit `CellSelection` local
names and local subscriptions. This lowers selected script locals into cells and
refreshes the view after their watched changes. Automatic project selection is
still pending.

Permanent `evaluator.test.cy` tests run natively with the rest of the suite.
The optional `--flat` gate checks the evaluator contract across the corpus
(static trees have empty plans; expression-bearing trees have code and records)
and runs complete emitted modules in jsdom with the real cell runtime. Cases the
older Zig reference cannot emit are accepted when the Cyna emitter produces a
valid module. Here “flat” means fixed structural topology; ordinary nested HTML
and SVG elements are supported.
