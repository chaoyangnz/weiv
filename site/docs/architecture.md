# Weiv Architecture

## Purpose

`weiv` is a frontend framework project intended to combine the strongest parts
of several existing frontend approaches while avoiding the parts that feel
ergonomically expensive.

The design motivation is:

- keep template, script, and style clearly separated
- avoid JSX as the primary UI authoring model
- avoid making explicit reactive wrappers the default way to write app code
- use compilation aggressively where it improves ergonomics and runtime cost
- preserve strong TypeScript support
- keep the runtime small and understandable

`weiv` is trying to be a practical, high-ergonomics frontend framework for
application developers.

## Direction

`weiv` is a compiler-first frontend framework.

The normalized vocabulary for this model lives in
[Terminology](./terminology.md).

The current direction is:

- `.weiv` single-file components
- TypeScript script blocks
- template-first authoring
- scoped CSS
- direct DOM browser output
- small runtime helpers
- compiler-owned state scheduling and patch planning

`weiv` should not center its default model around signals, refs, proxies, a
virtual DOM, or public effect graphs.

The default compiler transforms supported template-dependent local state and
managed project shared declarations through one observable/scheduling core.
Shared modules are transformed once, preserving canonical identity and native
live exports for components and ordinary JS/TS consumers. Ownership is established
by the managed build graph, not merely by parsing a module.

External mutable or uncertain dependencies need a known observable contract or
source-located diagnostic and adapter guidance. The supported data/effect contract
is bounded; arbitrary JavaScript inference is outside scope. See
[Reactivity](./reactivity.md) for the current source/release distinction.

Optional ecosystem/runtime companions are still valid, but they are no longer
part of the active top-level implementation track. The current architecture is
centered on the compiler/runtime foundation already on `main`.

The intended state split is:

- supported local and managed shared state become reactive automatically
- external mutable data uses explicit observables or subscription adapters
- both use the same tracking and microtask scheduling core

## Core Principles

### Template, Script, Style Separation

Single-file components are a first-class product choice. The framework centers
template-first authoring with ordinary TypeScript and ordinary CSS.

### Ordinary State First

The default component state model should feel like ordinary TypeScript
variables, object fields, and functions. Advanced runtime primitives can exist,
but they should not become the everyday happy path.

### Compiler First, Runtime Second

Whenever a concern can be solved at compile time without making the mental
model confusing, that should be preferred. The runtime should stay focused on
mounting, lifecycle, change propagation, and scheduling rather than becoming a
dumping ground for every abstraction.

### TypeScript Native

TypeScript is a design input, not a retrofit. That includes component prop
typing, event payload typing, template-to-script validation, editor tooling,
and diagnostics.

### Explicit Boundaries Over Magic

Weiv can compile aggressively without becoming mysterious. Rules should stay
learnable, explainable, and inspectable.

## Component Syntax

Current component shape:

```html
<template>
  ...
</template>

<script lang="ts">
  export interface Props {
    title: string;
  }

  export interface Emits {
    save: { id: number };
  }

  export let props: Props;

  function save() {
    emit("save", { id: 1 });
  }
</script>

<style>
  ...
</style>
```

Supported template features include:

- interpolation: `{{ expr }}`
- event binding: `@click="handler"`
- attribute/property binding: `:disabled="expr"`
- conditionals: `#if` / `#else`
- loops: `#for="item in items"`
- child components through capitalized tags
- slots: `<slot>`, named slots, fallback content, and `<template slot:name>`

## Component Contract

Component inputs use the conventional `props` binding:

```ts
export interface Props {
  title: string;
}

export let props: Props;
```

Component events use the Weiv-provided `emit` function:

```ts
export interface Emits {
  save: { id: number };
  cancel: null;
}

function save() {
  emit("save", { id: 1 });
}
```

`props` is explicit author code so TypeScript can name the input object. `emit`
is a framework-provided binding injected by Weiv. `export interface Emits` is
the conventional event contract for diagnostics and IDE tooling.

User-defined `emit` bindings conflict with the framework event facility and
produce a compiler diagnostic. The future IDE plugin should provide virtual
types for `emit` from `Emits` so normal TypeScript editing still works.

## Compiler Pipeline

The current pipeline is:

1. parser: SFC document with template, script, and style sections
2. parser: template AST
3. sema: `ScriptFacts` from the raw script text
4. sema: `TemplateBindings` from template-to-script binding
5. lower: target-neutral LIR
6. component aggregation: `ComponentUnit`
7. browser backend: `RenderTree`
8. browser backend: `BrowserComponent`
9. browser emit: JavaScript modules, scoped CSS, or app bundles

Zig owns the compiler pipeline, diagnostics assembly, lowering, code emission,
CLI, and app bundling. The Rust backend currently owns parser-heavy TypeScript
fact extraction through `oxc`, exposed to Zig as the script backend.

The parser layer owns document structure only. Script and style sections remain
raw text there so the parser representation is complete without making parser
own TypeScript or CSS semantics. Semantic analysis is where script facts and
template bindings become compiler facts.

`ComponentUnit` is the target-neutral component container after lowering. The
browser backend depends on it to build browser-specific representations.
`RenderTree` explains the retained browser DOM shape; `BrowserComponent` wraps
that render tree with the additional facts needed to emit JavaScript and CSS.
Whole app bundles additionally use an app graph to collect component and
runtime dependencies.

## Browser Output

The direct browser path emits retained DOM programs:

- `createDom(instance)`
- `updateDom(instance)`
- `destroyDom(instance)`
- region update functions such as `updateRegion_text_*`
- small structural helpers for boundaries, loops, slots, and movement

The direct path is the primary browser architecture. The older render/runtime
path remains useful for compatibility and comparison, but it is not the target
execution model.

## State And Scheduling

The state model is compiler-native scoped invalidation.

The mental model is:

- templates declare observation points
- the compiler defines update regions
- supported managed writes enqueue notifications through the common reactive core
- dirty bindings select dirty regions when possible
- regions reevaluate their own expressions
- generated patch code mutates retained DOM directly

Current region kinds:

- `text`
- `attribute`
- `conditional`
- `loop`
- `child`
- `slot`

Supported local and shared writes notify independently of callback origin.
Template handlers, external callbacks, timers and Promises all reach the same
microtask scheduler. State writes are immediate; initial mount is synchronous,
and subsequent state-driven DOM patches are batched.

Owned callback snapshots, timer wrappers and the legacy emitter have been
removed. The injected `weivUpdate` helper is also removed. See
[Reactivity](./reactivity.md#migration-from-legacy-mode) for migration options.

Unsupported visible stale-risk patterns should diagnose instead of silently
compiling into stale UI behavior.

`weiv emit invalidation-graph <path>` is the current inspectability command
for regions, dependencies, mutation sites, owned boundaries, and diagnostics.

## Composition

Slots are the current composition model.

Supported now:

- default slots
- named slots
- fallback content
- grouped named slots with `<template slot:name>`
- projected slot updates from parent-owned state
- switching between projected content and fallback after mount

Deferred:

- scoped slot props
- dynamic slot names
- portal/teleport semantics

## Diagnostics

Diagnostics are part of the product surface, not cleanup.

The compiler should prefer clear errors for patterns that look reactive but are
outside the supported managed/observable boundary. Source-located diagnostics already exist for
several template and composition mistakes, and invalidation-graph diagnostics cover the
current stale-risk cases. `analyze component` now also summarizes
current warnings and rewrite guidance, so users do not need to rely only on
`emit invalidation-graph` to understand the current precision model.

## Scheduling

The current direct-browser scheduling flow is documented in
[Runtime Scheduling](./runtime-scheduling.md).

That document is the source of truth for:

- immediate state writes and microtask-batched DOM timing
- local/shared observable notification waves
- subscription lifecycle
- current ordering semantics
- the exact guarantee around tracked captured references

## Router

The runtime includes a client-side router (`packages/weiv/src/runtime/router.ts`) that
integrates directly with emitted component modules through the existing
`mountIntoBoundary(start, end, props)` / `destroy()` lifecycle contract.

Key design choices:

- **Pure runtime, no compiler changes**: the router is a standalone TypeScript
  module that works with any component the compiler emits.
- **Observable route state**: `router.route` is an observable object. Components
  can subscribe to route changes through the same `subscribe()` mechanism used
  for shared state.
- **Nested routes with outlet management**: each nesting depth gets its own
  boundary comment pair. Parent components stay mounted while children swap.
  The reuse depth is calculated by matching the route chain, so only the
  changed levels are destroyed and remounted.
- **Navigation guards**: `beforeLeave` → `beforeEach` → `beforeEnter` execution
  order. Guards can return `false` to block, a string to redirect, or void to
  allow. All guards support async.
- **Link interception**: a document-level click listener catches internal `<a>`
  clicks and routes them through `push()`, with correct handling for external
  links, modifier keys, `target="_blank"`, and `download` attributes.
- **Scroll restoration**: per-history-entry scroll position saved before
  navigation, restored on popstate via a user-provided `scrollBehavior`
  callback.

The router does not require any special template syntax or compiler support.
A future phase could promote route concepts to compiler-level primitives (e.g.
`<Route>` template tags) for more ergonomic template authoring.

## Compiler Output Commands

Useful commands:

```sh
zig build run -- analyze component test/examples/todomvc/App.weiv
zig build run -- emit ast test/examples/basic/basic-counter.weiv
zig build run -- emit sir test/examples/basic/basic-counter.weiv
zig build run -- emit lir test/examples/todomvc/App.weiv
zig build run -- emit render-tree test/examples/todomvc/App.weiv
zig build run -- emit invalidation-graph test/examples/basic/basic-counter.weiv
zig build run -- emit js test/examples/basic/basic-counter.weiv
zig build run -- compile test/examples/todomvc/App.weiv dist/todomvc
```

The `emit` commands write to stdout by default. Add an output file argument to
materialize a representation.
