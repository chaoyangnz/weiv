# Cyna port architecture decisions

## ADR-001 — Parallel implementation and executable reference (2026-11-07)

Status: accepted for the first milestone.

Keep Cyna under `cyna-port/`, with compiler code following the existing phase
names. Leave production build/package entry points intact until cutover gates
pass. Use the unchanged Zig implementation as the executable behavioral oracle,
not a second handwritten parser. Preserve verified expectations as permanent
Cyna tests; rerun the live comparison explicitly when reference behavior changes.

Parity means equivalent accepted/rejected input, error precedence, byte ranges,
and eventually observable browser behavior. It does not require identical owned
representations or identical JavaScript formatting. Test runs pin the actual
compiler versions in progress notes. No full-port parity is claimed by SFC tests.

Consequence: temporary coexistence and two build toolchains, but individual
milestones are reviewable and failures are attributable. The Rust script backend
and TypeScript runtime remain dependencies rather than simultaneous rewrites.

## ADR-002 — Source-independent section records (2026-11-07)

Status: accepted; exercised by SFC parity tests.

The parser takes a borrowed byte slice for the duration of the call. Returned
records contain only half-open byte spans and value records. The compilation
owner, not every AST node, retains source bytes. This removes borrowed string
fields from the Zig shape and avoids copying each section's text.

A document's spans refer to exactly one immutable source snapshot. In this first
slice, the caller enforces that relationship; no unchecked pointers, recursive
heap ownership, or synthetic global source registry is needed. Introduce source
IDs/shared source services with the first multi-source requirement, rather than
inventing a registry before its callers exist.

The SFC parser does not read files, resolve imports, analyze TypeScript/CSS,
format diagnostics, or emit browser code. Later stages receive explicit inputs.

## ADR-003 — Preserve scanning quirks until deliberate changes (2026-11-07)

Status: accepted for compatibility, not an endorsement of every grammar edge.

Preserve the exact script attribute contract, section ordering and duplicate
precedence, literal-space name tokenization, and matching-tag depth scan. The
reference scanner is not an HTML/JS lexer: tag-like text in script strings or
comments can affect matching, and closing-tag range calculation assumes the
canonical spelling even when the matcher accepts a boundary with whitespace.

Targeted parity cases include these behaviors. Fixes must be separate language
changes with explicit tests and updated expectations, not accidental differences
introduced by the port. Template semantic parsing remains a later stage.

## ADR-004 — Typed parser failures; diagnostic rendering outside (2026-11-07)

Status: accepted for this slice.

Use Cyna typed error returns and a closed ParseError enum. No broad exception
catching, stringly typed parser status, or hidden failure-to-success fallback.
The test harness compares named errors against the Zig oracle, including
precedence. A future coordinator maps these errors to shared structured
diagnostics; it must not push CLI formatting into parser functions.

Cyna's unsupported `break` spelling is worked around using a condition-controlled
loop, with evidence in Cyna LG-50. This does not change Weiv's syntax or expand
this port into Cyna compiler implementation.


Implementation evidence: SFC parity passed for 112 inputs. Cyna LG-51 requires
splitting Boolean ordering and optional-absence guards into successive `if`
statements. This preserves error precedence and keeps workarounds local to the
implementation rather than altering stage contracts.


## ADR-005 — Cyna-native tests by default (2026-11-07)

Status: accepted following user feedback.

Everyday regression testing uses permanent `.test.cy` sources through
`cyna test cyna-port`. Test execution must not depend on Python, Zig, filesystem
fixture paths, or regenerating expectations. Reference inputs are embedded with
fixed expected errors/ranges, so a Cyna regression cannot rewrite its own oracle.

Retain Python only as optional migration tooling to execute both compilers and
compare the current repository corpus. An explicit `--update-reference-tests`
operation saves verified expectations; refreshes require normal diff review.
Handwritten regressions use separate test files and are never overwritten.

Tradeoff: the reference suite duplicates fixture text and captures a point in
time. The optional live comparison detects changes to tracked fixtures or Zig
behavior; direct Cyna tests remain deterministic and independently runnable.

## ADR-006 — Flat template arena and explicit static subset (2026-11-07)

Status: accepted; 18 native static-template tests and seven Zig reference
contract tests pass. The full native suite passes all 130 tests.

Store template nodes in document-owned preorder `List<TemplateNode>` storage.
Each node has a source span, a tagged element/text payload, and an exclusive
`subtree_end` node index. Direct children start at `node_id + 1`; repeatedly
advance to each child's `subtree_end` to enumerate siblings. Root enumeration
uses the same rule from index zero. Node IDs are stable while appending; callers
must not retain element borrows across growth. The arena is append-only, not an
incremental editing data structure.

Element payloads hold tag-name spans and ranges into a document-owned attribute
list. Text payloads hold source spans. No per-node heap allocation, recursive
owned child arrays, source copies, parent pointers, or borrowed source fields
are needed. An explicit stack of open element IDs drives parsing, so input
nesting does not consume the native call stack. A shared byte Span module is
used by both SFC and template records; the SFC name remains an alias.

This packet accepts static element/text trees, ordinary attributes, explicit
self-closing and HTML void elements, following Zig's quote/boundary and
whitespace rules. Interpolation, directives and slot outlets are not yet ported:
return an explicit `unsupported_syntax` milestone error rather than producing a
misleading static AST. That error is a temporary implementation boundary, not a
new Weiv language diagnostic. Normalization is deferred until dynamic syntax.

## ADR-007 — Dynamic syntax stays in the template stage (2026-11-07)

Status: accepted. All 147 native tests, nine new Zig dynamic contracts, and
77 live component comparisons pass. The static-only syntax boundary in ADR-006
is superseded; its arena and source ownership decisions remain in force.

Extend the existing tagged payload with interpolation expression spans and slot
outlet records. Directives live in a document-owned list; element records hold
start/count ranges, like attributes. Give every directive a full source span,
including structural directives for which Zig currently retains only text.
Expressions remain source spans, not a second TypeScript AST or evaluated values.

Parse attributes first, then split recognized directives before parsing children,
matching Zig error precedence. Convert a slot element into an outlet only after
its children/closing delimiter succeed, then validate its name and prohibited
directives. Keep slot attribute ranges in the outlet for source-aware inspection;
this also avoids removing middle ranges from a shared attribute arena.

Preserve legacy `on:`/`bind:` spellings and deprecation metadata. Recognize only
Zig's exact structural directive names: unknown `#` names remain attributes.
Preserve its first ` in ` loop separator, empty-expression behavior and legacy
empty target quirks rather than adding validation during the language port.
Normalization and script semantics remain separate later passes. The public
entry point becomes `parse`; remove the temporary static-only unsupported error.

## ADR-008 — Normalized arena with raw IDs and explicit branch ranges (2026-11-07)

Status: accepted. All 166 native tests and seven Zig normalization contracts
pass; normalized signatures match on 77 components plus 16 targeted inputs.

Normalization produces a separate flat preorder arena. Plain elements and slot
outlets retain raw node IDs instead of copying attributes or source strings.
A normalized directive-ID list selects only nonstructural directives from the
immutable raw document. The eventual compilation owner retains both documents;
IDs must only be interpreted with the raw snapshot supplied to normalize. No
stored aliases or hidden global owner registry are introduced.

Conditional/loop wrappers own normalized subtree ranges. A conditional stores
an explicit alternate-start index; the consequent starts immediately after its
wrapper and ends there, while the alternate ends at subtree_end. An absent
alternate has alternate_start == subtree_end. Loops and element/slot children
use the ordinary preorder child range. Wrapper spans preserve Zig's original
if/for element span rather than extending over a consumed else sibling.

Use an explicit work stack for sibling sequences, plain branch construction,
alternate markers and node completion. This preserves stack safety across deep
input without recursively allocating child arrays.

Preserve Zig's normalization semantics, including surprising combinations:
first #if wins over #for, #for wins over orphan #else, branch elements lose all
structural directives, and an adjacent element containing #else is consumed
regardless of its other structural directives. Whitespace-only text is already
omitted by parsing; real text/interpolation interrupts adjacency. These are
compatibility decisions, not language redesign or validation enhancements.

## ADR-009 — Rust script-analysis transport ownership (2026-11-07)

Status: accepted; all 176 native tests pass, including ten adapter tests.

Keep Rust's existing weiv_script_analyze/weiv_backend_free ABI unchanged. The
Cyna adapter accepts source/path strings, copies them into explicitly terminated
C buffers, invokes Rust synchronously, copies its returned JSON into an owned
Cyna string and frees the Rust allocation using only weiv_backend_free. Input
buffers use malloc/free and are deferred independently; never pass Rust memory
to libc free or retain an output pointer after freeing it.

Reject embedded NUL in either input rather than silently analyzing a truncated
prefix. This is an explicit transport boundary refinement relative to Zig's
current dupeZ call, not a change to valid Weiv source. Preserve backend JSON
including ok=false syntax diagnostics as a successful transport result; null
output means backend failure. JSON decoding and semantic facts remain in sema,
not the FFI module. Allocation failure is a distinct adapter error.

Installed Cyna lacks slice.ptr (existing LG-36); the spec's scoped std.c string
helper is not shipped. Use narrow raw-buffer fill/read operations inside the
adapter, with external allocation ownership explicit. Do not change language
semantics or broaden unchecked around application logic. Retain the Rust build
as a separate prerequisite rather than hiding a cargo invocation inside tests.


Native verification exposed LG-55: nullable C-pointer return values use an
incorrect aggregate ABI in both the installed and checked checkout LLVM output.
A small companion C bridge carries addresses as uintptr_t/c_size_t, checks zero
in Cyna, and delegates to the unchanged Rust functions. A static size assertion
makes the bridge's pointer-size assumption explicit. Allocation, byte copying,
NUL validation and JSON ownership policy stay in Cyna. Remove this workaround
only after adopting a compiler with native ABI regression evidence.

The project manifest links the retained release archive and iconv and compiles
the companion C file. Cargo is an explicit build prerequisite; Cyna tests use
project mode to keep native link settings. Test-source generation remains
optional migration tooling, never a prerequisite for permanent native tests.
Allocation-failure guards are implemented but not fault-injected; repeated-call
ownership tests and the null-response path do not claim exhaustive leak proof.

## ADR-010 — Owned typed script facts and validated JSON boundary (2026-11-07)

Status: accepted. All 193 permanent native tests pass, six Zig schema
contracts pass, and all decoded fields/code match on 77 component scripts.

Decode the retained Rust JSON into document-owned value records and lists in
sema. Immutable strings may share Cyna backing safely, but no returned record
borrows the temporary JSON tree or foreign buffer. DecodedScript carries facts
and transpiled JavaScript as separate fields; JavaScript is an output artifact,
not part of ScriptFacts. Preserve ok independently of component diagnostics.

Keep kind/severity/reason labels as strings for protocol compatibility. Use the
shared Span for source ranges and u32 for diagnostic line/column. Preserve record
order, nullable fields and the four default-empty state collections. All top-
level fields, including nullable ones, remain required as in Zig; state_analysis
null means empty state. Ignore unknown object keys for forward compatibility.

Deliberate internal-protocol hardening: accept only canonical nonnegative JSON
integer tokens for unsigned fields, with checked bounds and ordered spans.
Zig std.json also coerces numeric strings and integral floating spellings;
those are not emitted by the Rust schema. Reject such payloads explicitly,
rather than silently inheriting that library coercion. This changes malformed/
noncanonical adapter-payload acceptance, not valid component compilation.
Missing fields, wrong shapes, bad JSON, integer overflow and inverted ranges
return typed decode errors; never use unchecked JSON indexing before presence
validation or panic on externally supplied payloads.


Cyna's JSON parser rejects duplicate keys globally, including unknown keys;
this is another malformed-payload acceptance difference from Zig's typed
ignore-unknown-fields path. Decoder tests use explicit borrowed aliases for
owned helper records and fixture functions instead of global string constants
(LG-56 in the installed compiler; the checked source binary passes).

The optional parity tool calls the retained Rust ABI directly because Weiv's
existing Zig FFI wrapper uses allocator.dupeZ, removed by Zig 0.17. Its small
transport equivalent uses dupeSentinel; the actual Zig semantic decoder remains
the comparison oracle. No production Zig or Rust source change is needed.


Naming settled with the user: field/schema checks live in `script_json.cy`,
which describes the script backend's JSON contract. Its module comment makes
that scope explicit. The decoder imports it as `validation`: std.json owns
syntax parsing, validation owns response-field contracts, and
`decode_script_facts.cy` constructs the typed semantic records.

The optional full-field test generator groups assertions into small borrowed-
result helpers and batches independent test roots. Expected values still come
solely from the actual Zig decoder. The batched full-field comparison passes;
single-root compilation cost remains an investigation in Cyna LG-57.


## ADR-011 — Explicit model and operation ownership (2026-11-07)

Status: accepted. All 193 permanent native tests and 112 SFC comparison cases
pass. Model import review confirms dependency direction; formatting passes.

Use [ARCHITECTURE.md](ARCHITECTURE.md) as the current classification and input/
output contract map. Persistent representation modules import models/shared
value types. Operation modules own algorithms, pass-private state and failure
contracts, and import their input/output models. Named boundary modules remain
cohesive operations whose wire/transport responsibility is explicit.

Split SFC into `sfc/ast.cy` (SfcDocument/SfcSection) and `sfc/parse.cy` (source
scanning plus ParseError). Shared Span is imported directly from source.cy;
the representation does not depend on its parser. Rename the attribute splitting
pass to `template/split_directives.cy`; directive model records stay in ast.cy.

Move DecodedScript to `sema/decoded_script.cy`, a pass-result model depending on
script_facts.cy. ScriptFacts itself remains a semantic-only representation;
its model module imports neither the JSON decoder nor the emitted artifact.
Keep script_json.cy as the backend JSON boundary operation, with an explicit
module comment and the validation import alias. Models/operations have headers
stating their role; the architecture map records ownership and mutation limits.

This is a layout/dependency refactor. Preserve parser, normalization, transport
and decoder behavior and the existing protocol validation decisions. Update all
native consumers and optional migration generators to import operations and
models from their respective owners. No compatibility facade is needed for this
unreleased internal port; there should be one authoritative definition per model.

## ADR-012 — Slot manifest model and build operation (2026-11-07)

Status: accepted. All 204 native tests pass; entries/duplicate names/spans
match Zig on 77 components plus 12 targeted inputs.

slot_manifest.cy owns entries, duplicate reports and the manifest report model,
plus pure named/default lookup queries. build_slot_manifest.cy reads template
bytes and the associated raw/normalized documents and builds detached name
strings. Returned names have no raw-AST/source lifetime dependency; spans retain
the original template-relative locations for diagnostics.

Preserve Zig semantics: retain every outlet occurrence in encounter order and
report each later duplicate once, not once per matching prior occurrence. Default
(null) and explicitly empty names are distinct. Traverse both conditional branches
and loop bodies statically, without evaluating expressions or expanding loops.
An outlet's fallback subtree is excluded from manifest discovery, as in Zig's
walk; the flat pass must jump to subtree_end after recording an outlet.

The build operation is pure with respect to source and input models; duplicates
are report data for binding, not a failing build. Imported-component manifest
resolution is a later injected boundary and performs no filesystem work here.


Pure query implementation uses indexed read-only borrows rather than value loop
bindings because of Cyna LG-58. This is a safe application-level workaround;
model contents and the manifest build contract remain unchanged. The reduced
program and both compiler identities/results are recorded in the Cyna ledger.

## ADR-013 — Template binding models and immutable manifest input (2026-11-07)

Status: accepted. All 220 permanent native tests pass; bound facts and complete
diagnostics match Zig on 77 components plus 13 targeted inputs.

TemplateBindings owns component references, expression references, diagnostics
and the own-slot manifest. Expression source is a template-relative Span; names
and diagnostic text are detached strings. The binder reads source bytes, paired
raw/normalized templates and ScriptFacts without mutation.

Use ComponentManifests as an explicitly supplied immutable catalog of imported
component manifests. Lookup returns a catalog ID, not an opaque pointer or an
I/O callback. Project resolution constructs that input before binding; absence
means cross-component slot facts are unavailable, independently of lexical tag
resolution. Resolver failures stay outside this pure pass.

Walk normalized preorder with an explicit loop-scope end stack. Bind iterable
expressions before introducing aliases; pop aliases at their subtree boundary.
Component slot checks inspect direct normalized children only, as Zig does.
Preserve reference encounter/dedup order, call-flag upgrades, helper warnings,
diagnostic messages/order/severity and legacy span-offset arithmetic. This is
the current lexical scanner contract, not a new JavaScript lexer.


Manifest ownership transfers from SlotManifestReport through explicit named-
field replacement capture (@ const own_manifest). Direct projected owned-field
handoff is rejected as designed by Cyna; this is ordinary ownership handling,
not a language gap or a reason to clone the model. Existing LG-58 indexed-borrow
workarounds are used consistently in the new scope/catalog/binding operations.


Diagnostic coordinate origin is explicit in BindingSource (template/script).
Reserved emit-binding spans come from ScriptFacts; all other binding spans come
from the template. Preserve their numeric Zig ranges but make their coordinate
space unambiguous for future compilation-unit mapping. The optional comparison
checks this added origin against the reference diagnostic kind as well as every
legacy diagnostic field. The legacy interpolation-offset precision issue is
recorded separately in WEIV_FRICTION.md.

## ADR-014 — LIR node IDs and owned child-edge lists (2026-11-07)

Status: accepted; 234 native tests and live parity for 77 components plus 25 targeted inputs pass.

LIR has an owned node arena and root/child ID lists. Component provisions may
merge interleaved source children by name, so a preorder-only subtree range is
insufficient for their logical child order. Child edges remain IDs rather than
recursive Node storage; no native recursion is needed for lowering or model drop.

LIR owns attributes, effects, provisions and copied expression-reference lists.
Text/tag/expression/slot names use spans in the retained source snapshot, so LIR
has no raw/normalized/binding-container lifetime dependency. Expression lookup
uses exact source-range identity within that snapshot, matching Zig's pointer+
length identity rather than text equality. Retain node spans as extra provenance.

Lower in two linear traversal passes plus per-component provision grouping:
validate placement/build normalized-to-LIR IDs first, then construct owned edges
and payloads. A direct projected template group contributes its children without
a LIR node; ordinary projected children retain their node while slot directives
are stripped. Keep first-provision encounter order and append matching children.
Default vs explicitly empty names remain distinct. Ordinary component attributes
are discarded as in Zig; event/bind effects retain their encounter order.

Placement checks follow normalized parent relationships, not source ancestry:
slot assignment is allowed only on direct component children. Structural wrappers
do not grant that placement. A template group outside a direct named projection
fails InvalidSlotTemplatePlacement before other slot-placement checks.

The installed Cyna 0.4.1 general optional-absence expression lowering bug also
affects `return b is none`. An explicit branch preserves the intended Boolean
result. The reduced reproduction passes on the current Cyna checkout; evidence
is appended to the existing LG-51 report, not classified as a new defect.


## ADR-015 — owned compilation reports and explicit source origins (2026-11-07)

Status: accepted; 245 native tests and coordinator parity on 77 components plus 25 targeted inputs pass.

`component_unit.cy` owns the persistent complete ComponentUnit and partial
ComponentCompileReport models. `compile.cy` is the in-memory coordinator;
`diagnostics.cy` owns stage/failure/diagnostic records; `map_diagnostic_span.cy`
performs checked fragment-to-file mapping. Models import only models. Keep
DecodedScript bundled as facts plus a separately named JavaScript artifact,
without duplicating ScriptFacts fields across the coordinator and its report.

The coordinator takes owned immutable source/path strings and a borrowed
immutable ComponentManifests catalog. It performs no filesystem lookup. Earlier
stages run before script transport; invalid script stops before binding.
Binding diagnostics stay nonfatal, matching Zig; hard lowering failures preserve
all preceding outputs. Transport/decode failures also return inspectable reports,
rather than escaping as unstructured exceptions. The failure record stores a
typed stage and the original snake-case pass error code. Exhaustive adapters
keep operation error enums out of model dependencies. The runtime has no Zig-like
anyerror model, and a pass-specific error union in a persistent model would
invert that dependency direction.

`take_unit` validates every required result before detaching any owning field
with Cyna's optional `take`. A consumed marker prevents repeated extraction.
Source/path strings, diagnostics and small SFC coordinate records remain in the
report so diagnostics can still be mapped after transfer. Units retain their own
immutable strings and owning stage data; destroying a report or caller-local
input does not invalidate the unit. Failed extraction leaves the report intact.

Diagnostic spans retain SourceOrigin.file/template/script, avoiding the legacy
Zig coordinator's treatment of template binding coordinates as absolute file
positions. Mapping checks ordering and fragment bounds; invalid/unknown ranges
return none without clamping. Existing binder numeric offsets are preserved.
This packet adds no heuristic parser/lowering span search and no line/column or
CLI formatting layer: hard stage failures retain their stage/code with absent
spans and a code message until diagnostic presentation is ported. Those limits
are explicit; no full diagnostic presentation parity is claimed.

The supplied-manifest regression reads nested catalog storage through an
explicit indexed borrow. The chained `entries[0].manifest.entries.len()` query
is rejected by installed Cyna; reduced reproduction and current source-binary
observations are recorded in LG-59. This is isolated from compiler application
semantics; the coordinator does not require unchecked access or compiler edits.


## ADR-016 — lexical inputs before template-function generation (2026-11-07)

Status: accepted; 261 native tests and 77-component/16-targeted-case parity in both selection modes pass.

`lower/template_functions.cy` owns TemplateFunctionInputs/TemplateFunctionInput
and generated TemplateFunctions/TemplateFunctionRecord. Capture one owned list of
script names plus each expression's exact source span, active loop aliases and
optional handler argument. `collect_template_functions.cy` performs an iterative
preorder walk of normalized/raw templates and copies lexical scope snapshots.
It has no foreign or JSON dependency. Do not discover these inputs from LIR:
metadata collection deliberately includes template projection-group effects that
runtime lowering later discards. Scope begins after a loop's iterable expression
and expires at the normalized subtree boundary. Preserve raw binding/import
order and duplicates; wrapper generation handles innermost alias shadowing.

`build_template_functions.cy` filters unsupported expressions with the retained
Rust validator, selects mutations through the real module-state probe when pure
render expressions are excluded, and emits function wrappers. Public `append`
is shared with future runtime evaluator planning. Preserve direct-handler,
runtime conditional-handler and ordinary-expression wrapper bytes. Include pure
expressions by an explicit option. Caller prefixes are copied verbatim; generated
ranges refer to the returned complete buffer, and no array suffix is implicit.
`sema/decode_mutation_probe.cy` is the schema validation boundary for the small
Boolean probe result; it is not a persistent semantic model. New foreign calls
reuse existing scoped buffers/address carriers and Rust response cleanup.

Use parser-provided expression ranges for template mappings instead of Zig's
text search from the enclosing node's start. For `<a #if="a">`, the legacy search
can identify the tag name rather than the condition. This is a deliberate source
mapping correction, not a generated-code change. The optional oracle compares
unchanged Zig output bytes and legacy mappings, then independently substitutes
pointer-offset identity for the text search to check corrected ranges.
Weiv feedback records a reproducible example and the precise difference.

Unsupported syntax is skipped like Zig's collector, but foreign allocation/
transport errors are propagated as TemplateFunctionError.backend_failure rather
than being swallowed as unsupported syntax. Malformed probe JSON has a distinct
invalid_backend_response error. Reserved local prefixes keep their hard error,
even for a shadowed local. The standalone append buffer may contain a partial
wrapper on failure, matching the reference primitive; build discards it.

LG-60 records rejection of `catch` on an alias result to an owned-resource type,
verified in installed 0.4.1 and the current checkout. Probe decoding instead uses
a checked key index and a scoped borrowed DOM value. This preserves schema
checks without an owned clone. The reduced scalar-alias and typed-try controls
are documented alongside the failure; no Cyna compiler source is modified.


## ADR-017 — owned browser tree and explicit reference-allocation traversal (2026-11-07)

Status: accepted; 273 native tests and browser parity for 77 components plus 33 targeted inputs pass.

`backend/browser/render_tree/tree.cy` defines the browser-specific persistent
model; `lower.cy` operates on valid target-neutral LIR. Do not add browser tree
fields to ComponentUnit or browser dependencies to the component coordinator.
The tree owns flat node storage, root/child ID lists, copied attributes, split
effect lists and slot provision records. Reuse the target-neutral attribute/
effect value types without borrowing their owning arrays. Text remains a span
in the retained template source. After construction the tree has no LIR/raw/
normalized-container lifetime dependency. Nodes preserve their source spans and
one-to-one LIR arena IDs; logical edges may reorder those IDs.

Reference IDs follow Zig's logical traversal order, not physical arena order.
Elements allocate one reference after their children; components allocate three
after all provisions. Conditionals, loops and slot outlets allocate three before
their children; interpolations allocate one immediately, text none. Named slot
merging means traversal must follow provision edges rather than source-node IDs.
Use an explicit enter/finish work stack to assign base references, then construct
payloads in a second pass with stable IDs. All storage/traversal/drop stays
nonrecursive; time is linear in valid nodes/edges/effects/attributes.

Effect partitioning is stable: retain all binds and events in their original
order within each separate list. Slot directives and discarded component
attributes have already been handled by target-neutral lowering. This operation
does not evaluate expressions, discover reactive regions, allocate a second
expression table, emit DOM operations or resolve project files.

Borrowed variant helpers pass a whole payload record by reference before reading
its owned fields. This also avoids installed Cyna's checked projection failure
for a collection field reached directly through a borrowed union capture; the
reduced example and supported helper form are recorded in Cyna LG-61. Helpers
remain private pass implementation, with no unchecked code or compiler changes.


## ADR-018 — owned tracked-path inventories with fact-only classification (2026-11-07)

Status: accepted; 289 native tests and parity for 77 components plus 16 targeted inputs pass.

`backend/browser/tracked_roots.cy` defines TrackedKind and TrackedRoot;
`tracked_paths.cy` defines TrackedPath/TrackedPaths plus pure ID queries.
`classify_tracked_roots.cy` reads only ScriptFacts, not ComponentUnit. Its
find_visible_binding query returns a zero-based facts index, while all persistent
root/path IDs are one-based and equal to their collection index + 1. Typed kinds
have a pure stable label function for parity/inspection. Models own strings and
collections; there is no allocator field, borrowed component pointer, or separate
list of buffers holding borrowed path prefixes alive.

`collect_tracked_paths.cy` reads immutable script/LIR facts plus a template-source
span and appends to an explicitly supplied table and leaf-ID list. Callers retain
the same source coordinate space used by LIR expression facts. A present exact
expression range filters candidate roots by bound references; an absent range
uses the legacy fallback scan. Script/LIR inputs stay immutable during an ordered
collection session. The finished table owns all names/prefixes independently.
Each accepted dotted leaf ensures its root and every canonical prefix, retaining
first encounter order and stable parent IDs. Existing caller IDs are retained;
new leaf IDs append only when absent.

Preserve classification priority import > props > local. Local tracking uses the
first visible binding, exact mutable/immutable kinds, noncallable status, no
matching alias target and no whole-binding mutation. A non-null empty member path
still denotes a member mutation. Props matching uses the recorded binding name
without additionally requiring the export flag, just as in Zig.

Keep the reference scanner's ASCII identifiers, four whitespace bytes, keywords,
spread/property distinction, dotted canonicalization and method-call boundary.
It does not lex strings/comments or optional/computed access as JavaScript;
bound filtering checks root names, not individual token occurrences. A root also
used outside a quoted/commented path can therefore leave a spurious tracked
path. Native/parity tests preserve this known behavior and WEIV_FRICTION.md
records it for a separate semantic precision change. Do not reuse the template
binder scanner here: its contract and keyword/quote behavior differ.

This is a reusable analysis operation, not an implicit coordinator side effect.
Region/inspection/emission consumers control the order in which expression
requests populate their shared inventory. Dependency closure and reactive region
allocation remain separate later operations.


## ADR-019 — explicit dependency policy and iterative helper/subtree collection (2026-11-07)

Status: accepted; 308 native tests and parity for 77 components plus 17 targeted inputs pass across both imported-call policies.

`backend/browser/dependencies.cy` owns DependencyList and its pure membership
query. `collect_dependencies.cy` operates on immutable ScriptFacts/LIR plus
source ranges and explicit locals. DependencyOptions is an operation input;
retain_imported_calls is not mutable policy stored in the persistent result.
No ComponentUnit pointer, allocator or borrowed source names are retained.
Dependencies own their strings and preserve stable first-encounter order.

Exact LIR source-range identity selects ordered bound references and their call
flags; absent ranges use the legacy ASCII scanner. Reuse first-visible-binding
and imported-binding queries from browser classification. A visible called
binding is always included, but only callable bindings with helper facts expand.
Append all helper reads before calls, then expand each call depth-first before
its next sibling. Unknown/imported helper read/call names remain until explicit
retain_visible filtering. The imported-call policy filters direct expression
calls only; helper-reported calls are appended independently, as in Zig.

HelperFrame and a path-local name trail replace native recursion. Do not replace
the trail with a global visited set: preserve reference traversal/revisit order.
Retain_visible stably rebuilds an owned list, keeping preexisting duplicate
visible entries as the reference compaction does. Names from helpers need not be
visible until that explicit consumer-requested filter runs.

collect_node handles one browser subtree, letting region planning choose its
structural ownership. Use an explicit node/leave-loop task stack, private copies
of supplied locals, and aliases pushed after the iterable expression. HTML events
are excluded; HTML binds, both component effect lists and component provisions
are included. Component provisions follow logical grouped order, not arena
order. Conditionals traverse condition/yes/no; slot outlets include fallback.
Private borrowed-payload helpers retain the LG-61 workaround for owned fields.

The fallback scanner intentionally keeps the same quote/comment precision limits
as the reference; bound references preserve deduplicated call upgrades and
reference ordering. Names are not resolved binding identities, so lexical-local
shadowing remains an explicit precision boundary, not silently changed here.
Reactive region construction remains a later composition of this operation and
the tracked-path inventory.


The name-only boundary has a concrete shadowing reproduction: a loop-local `f`
calling `f()` can expand the unrelated script helper `f`'s reads. The actual Zig
and Cyna outputs are covered in targeted parity and a native regression, with
exact expected/actual context in WEIV_FRICTION.md. Keep this precision correction
separate from dependency collection mechanics; resolved lexical identity will
need to reach helper selection and visible compaction together.


## ADR-020 — owned region graphs with explicit structural ownership (2026-11-07)

Status: accepted; 324 native tests and graph parity for 77 components plus 20 targeted inputs pass.

`backend/browser/region_graph.cy` owns RegionKind, Region and RegionGraph;
`build_region_graph.cy` constructs the graph from immutable template bytes,
script/LIR facts and a valid render tree. Reuse existing dependency/path operations
instead of introducing another name scanner or dependency algorithm. Graph
models retain no allocator, ComponentUnit pointer or mutable imported-call flag.
Region planning always retains imported calls, matching the reference build API.
Each graph owns its path inventory, dependency/name strings and region arrays.

Regions have typed kinds with stable labels. Region/path IDs remain one-based;
render reference/node IDs remain the existing zero-based values. A checked
region_index query makes that conversion explicit. Added node_id and template
span provenance identify the originating render/LIR node without an owning
back-reference. Names and import hints copy immutable string data; spans remain
coordinates in the retained template snapshot. DependencyList ownership moves
through explicit named-field replacement capture, avoiding redundant copies.

Only ordinary elements recurse during region discovery. Emit their bind regions
before visiting children. Interpolations make text regions. Conditionals, loops,
components and outlets each make one region that owns its entire subtree; their
descendants contribute dependencies but do not become direct update regions.
Use an explicit work stack for ordinary-node traversal and the existing iterative
subtree collector for dependency closure.

The shared path table follows region encounter order. Expression regions collect
paths from their expression. Conditional/loop regions collect only their header
paths, though their dependencies include descendants. Component regions collect
only direct bind/event effect paths, though projected content contributes to
dependencies. Slot regions include fallback dependencies and no paths. Preserve
these distinctions; do not accidentally promote descendant paths/regions.

Precise import hints are limited to text/attribute expression regions with one
visible dependency and one leaf path: the root must be imported, match the
single dependency, and the ASCII-trimmed original expression must equal the
canonical path without internal whitespace. Structural/child/slot regions keep
no hint. Empty-dependency/constant expressions still retain regions.

The optional oracle compares all legacy graph fields with actual Zig and checks
added provenance against independently allocated render references/spans. No
legacy scanner, lexical identity or hint-selection behavior is corrected in this
packet. Browser artifact assembly and emission remain separate operations.


## ADR-021 — owned browser assembly and independent scoped CSS artifact (2026-11-07)

Status: accepted; 341 native tests plus CSS parity for 77 components, 42 targeted styles and 33 path/hash boundaries pass.

`backend/browser/component.cy` owns ComponentUnit, RenderDocument and RegionGraph.
`build_component.cy` consumes a complete unit and assembles these artifacts using
the existing pure lowering/analysis operations. There is no borrowed unit pointer
or required destruction order among externally owned stage containers. Retaining
the complete unit keeps source spans and template coordinates meaningful while
all render/graph collections retain their independent ownership. Browser assembly
performs no filesystem access and does not add browser stages to compile.cy.

`compute_scope_id.cy` is a reusable operation on exact source-path bytes. Match
Zig 0.17's seed-zero Wyhash and uppercase `w` plus sixteen zero-padded hex digits.
Implement one-shot hashing using 32-bit limb products in u64 values, with explicit
little-endian loads, rather than adding a C hashing bridge or relying on platform
hash randomness. Goldens cover all standard seed vectors; live comparison covers
short/long boundary paths, UTF-8 paths and the 48-byte processing boundary. Do not
normalize paths or change hash algorithms during the port: scope IDs are shared
with the forthcoming DOM/JavaScript emitter.

`emit/emit_scoped_css.cy` reads a borrowed complete unit and returns an owned CSS
string. The public rewrite primitive accepts raw stylesheet bytes and a scope
selector independently. CSS output remains separate from browser planning models;
invalid style syntax does not discard an otherwise inspectable compiled unit.
Qualified selectors, root/descendant selector pairs, whole :global escapes,
comments/whitespace and at-rule behavior match the reference. Explicit range
frames replace recursive media/supports/layer group traversal. Frame/Product
records remain private operation state, not persistent models.

Unterminated CSS rules remain a typed CssError. An explicit append_diagnostics
operation appends the exact style.unterminated_rule fatal message with emit stage
and full-file style-content coordinates. Added CompilationStage.emit belongs to
the shared diagnostic model. No CSS error is injected into frontend compilation
or browser construction. Existing diagnostic context/formatting limits remain;
line/column presentation is not claimed as ported here.

Keep confirmed reference limitations explicit: container/scope groups remain raw,
comment braces inside declarations can trigger a false unterminated-rule error,
and at-rule names match prefixes. Native/live comparisons preserve these cases;
WEIV_FRICTION.md records reproducible expected/actual behavior for a separate fix.
No Cyna compiler changes or new language gaps were needed for this packet.


## ADR-022 — shared JavaScript primitives and an explicit static module slice (2026-11-07)

Status: accepted implementation; validation recorded in Packet 19.

Keep JavaScriptModule and ImportOverride as noun models; put assembly in
emit_static_module and each algorithm in a separate operation. The artifact owns
code, scope_id and css independently of source and browser lifetime. No emission
algorithm, backend transport or filesystem policy belongs in BrowserComponent.

Port complete static output before dynamic updates. Validate the render forest
first and reject interpolation, effects, structures, child components and outlets
with unsupported_template. Empty templates and multiple roots are supported.
Match emitModuleWithSelection with explicit empty managed-cell/local selections;
do not imply that this slice implements project analysis or selects state.

Use the retained Rust cell-lowering ABI for setup, with four scoped NUL-checked
inputs and freed responses. Decode the wire envelope separately, requiring code
and nullable error fields and preserving known typed failure categories. Reuse
string/entity writing, imports and tracked-state metadata for later dynamic
emission. Metadata already accepts general graphs. Preserve reference import
rewrites/order and known malformed edge output for comparison, recording defects
in WEIV_FRICTION.md rather than changing compatibility silently.

Store immutable JS fragments and all 2,125 named HTML entities as ordinary Cyna
source. No Python-generated permanent tests or runtime generator is required.
Static DOM creation uses an explicit enter/finish stack and existing render IDs,
including SVG/foreignObject namespace transitions and scope markers. Mount,
refresh, props/handlers/slots and destroy use the reference lifecycle fragments.
Runtime validation must execute emitted Cyna modules with the actual cell runtime.

Use operation-specific private work record names: generic lists of distinct
private Visit types collide in both tested compilers (LG-64). StaticDomVisit
contains optional parent reference IDs, not strings. The installed compiler also
requires explicit success return in void!Error validators (LG-63); retain that
local workaround. The source-built compiler passes the
reduction, but this port continues targeting the installed binary. Next, define
an evaluator/cell-expression plan and add interpolation/bind updates separately
from persistent render data and module assembly. Full dynamic structures and the
project driver remain later stages.


## ADR-023 — typed evaluator side table and fixed DOM update emission (2026-11-07)

Status: accepted implementation; validation recorded in Packet 20.

EvaluatorPlan/EvaluatorRecord are emission-only models, separate from render
nodes and the region graph. Each zero-based evaluator ID has a typed argument
(render, event or payload), site kind, originating node/effect index, and exact
template/generated byte ranges. The code field owns comma-separated evaluator
closures. Model lookup is a pure query; Rust transport, traversal, validation
and code writing remain separate operations.

The reference clones its render tree and substitutes NUL-prefixed marker strings
for expressions. Cyna retains the immutable source-backed render tree and builds
a typed side table instead. DOM emitters invoke evaluators by typed records;
no parser, region scanner or backend transport receives a hidden marker string.
Region/path analysis continues to read the original expressions. IDs are local
to a plan paired with that exact browser snapshot; source spans still require
the retained template. Generated offsets refer to the owned code string.

build_evaluator_plan walks logical edges using domain-specific EvaluatorTask
records. It validates render expressions with the real Rust expression predicate,
handlers with the real handler predicate, then reuses build_template_functions
append for lexical closures and handler normalization. Preserve reference order:
node/header, element bindings, element handlers, descendants; component bindings/
payload handlers precede projected slots; condition branches visit consequent
before alternate; iterable validation precedes adding its loop local. An explicit
leave-loop task restores locals. Repeated loop names retain lexical shadowing.

The complete module operation supports fixed DOM structure with interpolation,
bindings and element events. It emits evaluator closures through the existing
Rust lower_cells_with_expressions transport and stores them in the instance scope.
DOM creation and update operations share typed evaluator references; full/selective
updates follow the original region graph. Check region kind, reference, node and
binding target before routing updates. Bindings retain exact class/static merge,
boolean property/attribute, value property/attribute, style, aria and general
attribute behavior. Event callbacks refresh scope and use the normalized evaluator
result. Structures/components/outlets remain explicit unsupported_template errors.

Continue using explicit empty managed-cell/local subscription selection. This
supports props watchers, event dispatch and ordinary script closures, but does not
select reactive script locals. A template assignment to an unselected local must
retain cell_template_untracked_assignment_unsupported. Full cell/managed selection
is a separate operation/driver concern; do not silently widen the selection.
Static API compatibility remains a validation wrapper over shared module emission,
not a second assembly pipeline. Runtime parity is required for both; generated
byte identity is superseded by ADR-031.

### ADR-024: Caller-owned local cell selection

The browser module emitter accepts a CellSelection value containing local names
and local subscriptions. select_cells validates each selected name against visible
mutable or immutable script bindings, excludes the props binding, and produces
Rust's JSON name array in script binding order. Setup reads selected cells through
`.value` and subscribes selected locals to caller-specified dirty binding names.
The existing emit entry supplies an empty selection for compatibility. Project
state analysis will own automatic selection and pass the result to
emit_with_selection; emission itself stays independent of filesystem discovery.
The same caller-owned selection carries managed publisher specifiers/names and
observable import watchers. Managed subscriptions import numbered moduleState
publishers. Nonpublisher imports use the existing observable adapter and honor
explicit dirty binding names. A publisher-backed import suppresses that adapter.

### ADR-025: Region-derived local selection is a bounded backend helper

select_local_state reads the browser region graph and script facts to choose
locally declared cells that directly supply rendered regions. It does not
replace Zig's state_dependencies project analysis, which also traces ownership,
callbacks, module graphs and write-only state. The default emit entry remains
explicitly empty until a project driver owns that broader decision. The helper
uses indexed reads of owned selection lists after a native failure with by-value
iteration; no language defect is asserted without a reduced reproduction.

### ADR-026: Conditional descendants belong to one browser region

Conditional DOM emission uses source-backed render children and typed evaluator
records without rewriting the tree. The condition's region owns all descendant
updates, matching the reference region graph's structural boundary. Creating a
branch initializes its element/text refs, and updating that branch evaluates its
interpolations and bindings. The generic region emitter skips descendant records
when they are owned by a conditional. Full and dirty updates both route through
one conditional helper. The current fixed-topology implementation rejects nested
structural/component/slot children and retains structural byte parity as an open
gate; the browser behavior for supported cases has a jsdom regression.

### ADR-027: Keyed loop entries own their DOM refs and item scope

The generic loop helper uses start/end boundaries per entry and the reference
key rule (`item?.id ?? item`). It retains entry refs and the current item in a
closure, updates the lexical scope on reuse, moves boundaries to match iterable
order, and removes detached entries. The loop's one region owns descendant
updates. DOM creation accepts a refs owner and event scope, allowing the same
element/event operation to serve root, conditional and loop contexts. Loop bodies
with nested structures or components remain gated until their lifecycle and
refs ownership can be represented; generic loop browser behavior is verified
with real runtime reorder, binding, interpolation and event cases.

### ADR-028: Child component refs own imported mount handles

An imported component creates start/end comments and stores the child
mountIntoBoundary handle at its render ref ID. Its child region passes fresh
typed evaluator prop objects and payload callbacks on parent updates. Parent
destroy calls the handle's destroy operation. Component regions with no effects
are still emitted from the immutable graph, since they have no evaluator record
to drive the region traversal. Project import resolution and projected slot
ownership remain separate operations; neither is inferred inside JS emission.

### ADR-029: Slot outlets own fallback refs and supplied handles

A slot outlet creates its own start/end comments and stores either a supplied
mount handle or `false` for fallback. Its one region owns fallback descendant
updates. The outlet checks instance.slots on each update, mounts and updates a
supplied slot handle when present, destroys that handle on withdrawal, and
recreates/upgrades fallback content. The caller's supplied mountIntoBoundary
implementation must replace content between the comments, matching the
reference projected slot contract. Parent-side projected slot helpers remain
separate because they own another refs array and the parent lexical scope.

### ADR-030: Projected slot helpers retain parent scope and own refs

A component provision creates a mountProjectedSlot helper with its own refs
array and a refresh closure into the parent instance. Fixed DOM content is
created and updated there, including interpolation, bindings and events. The
component receives a map of default/named slot factories. Parent updates reset
that map and ask the child handle to update. Projection descendants remain under
the component's single region. Nested structures/components in a projection
are gated until their cleanup and ref ownership are represented explicitly.

## ADR-031 — generated output has semantic, not byte, parity (2026-11-09)

Status: accepted; supersedes generated JavaScript/CSS byte-identity gates.

The Cyna browser emitter must compile the same accepted source and produce
equivalent observable behavior. Acceptance covers program success or failure,
error precedence, exports and imports, generated identifier/reference
consistency, DOM structure and updates, event behavior, scheduling, cleanup,
and equivalent CSS selector and cascade behavior. Generated JavaScript and CSS
may differ in formatting, path-derived scope IDs, equivalent helper spelling,
and collection order when that order is not observable.

Byte identity remains useful as a precise diagnostic in focused oracle tests
and is required for explicit public byte contracts, including inspection text
and structured diagnostic formats. It is not a release requirement for generated
JavaScript or CSS. Semantic comparisons must not erase meaningful order:
JavaScript execution order, CSS cascade order, and any ordering visible to users
remain part of the contract.
