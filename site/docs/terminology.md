# Weiv Terminology

This document normalizes the words we use for Weiv's compiler-native UI model.
The terms borrow ideas from retained-mode UI, immediate-mode reconciliation,
incremental computation, and compiler-driven frontend frameworks, but the names
below are the Weiv vocabulary.

## Core Model

### Component Contract

The conventional script-level contract between a component and its parent.

Current contract names:

- `export let props: Props` declares component inputs.
- `emit(name, payload)` sends component events to parent `@*` handlers.
- `export interface Emits` describes the event payload contract for diagnostics
  and future IDE tooling.

`emit` is a Weiv-provided binding. User code should not declare, import, or
shadow it.

### Observation Point

A place in the template where rendered output depends on an expression.

Examples:

- text interpolation: `{{ count }}`
- bound attribute: `:disabled="count <= 0"`
- branch condition: `#if="visible"`
- loop source: `#for="item in items"`
- child prop expression
- slot projection expression

Observation points are compile-time facts. They are not runtime subscriptions.

### Binding

A script-level name that the template can read.

Examples:

- `count`
- `items`
- `props`
- `visible`

Bindings are the units the compiler uses to explain what template output may
depend on. A binding can be dirty because its reference changed, because a known
in-place mutation happened, or because the compiler must conservatively assume
it changed.

### Region

The smallest generated update unit Weiv currently plans to patch.

Examples:

- text region
- attribute region
- conditional region
- loop region
- child region
- slot region

A region owns retained DOM handles and knows how to refresh one part of the DOM.
Regions are Weiv's equivalent of an update island, invalidation target, or
retained UI node.

### Dependency

A relationship from a region to the bindings that may affect it.

Example:

```html
<button :disabled="count <= 0">{{ label }}</button>
```

This creates two region dependencies:

- the disabled attribute region depends on `count`
- the text region depends on `label`

Dependency analysis is compiler-owned. It should be visible in
`emit invalidation-graph`.

### Dirty Binding

A binding that may have changed since the last flush.

Dirty does not mean "definitely visually different". It means "regions depending
on this binding should be considered for update". Region code may still compare
old and new values before patching the DOM.

### Dirty Region

A region selected for update because one or more of its dependencies are dirty.

The managed scheduler merges dirty dependency keys into component jobs; compiled
region guards select the affected DOM updates.

### Flush

The scheduled update pass that delivers reactive notifications and component jobs.

A flush should:

1. collect dirty bindings or dirty regions
2. run only the relevant region update functions when possible
3. fall back to a coarse component update when analysis is uncertain
4. avoid updating destroyed component instances

### Patch

The direct DOM mutation performed by generated region code.

Examples:

- update a text node value
- set or remove an attribute
- mount or unmount a branch
- reconcile loop children
- update child props
- refresh projected slot content

Patch is not the same as flush. A flush chooses what may need work; a patch is
the actual DOM change.

## Scheduling

### Managed Boundary

The component and project modules actually owned by Weiv's build. Supported
state declarations and writes inside it use the common reactive core. External
mutable dependencies require known observable/adapter contracts or diagnostics.
Parsing a module alone does not grant ownership.

### Owned / Unowned Callback Boundary (Legacy)

The retired legacy model distinguished callbacks wrapped by Weiv from external
registrations. Its synchronous checks, wrappers and injected `weivUpdate` helper
have been removed. These terms remain only to explain historical material.

The managed default does not use callback origin to decide whether supported
writes notify. Template events, timers, Promises and external callbacks all use
the same microtask scheduling mechanism. Raw external references remain outside
the observable boundary regardless of callback origin.

### Conservative Fallback

A deliberate broader update when the compiler cannot prove the exact affected
regions.

Fallbacks are allowed, but they should be explicit in generated structure and
inspectable in `emit invalidation-graph`. The model should prefer correct
coarse updates over silent stale UI.

## Inspectability

### Invalidation Graph

The compiler's explanation of how template observation points, bindings,
regions, mutation sites, and owned boundaries relate.

The command is:

```sh
zig build run -- emit invalidation-graph path/to/Component.weiv
```

The canonical command is `emit invalidation-graph`.

The invalidation graph is the primary debugging surface for stale UI questions.

### Diagnostic

A compiler or invalidation-graph message explaining a pattern that is unsupported,
ambiguous, or likely stale.

Diagnostics are part of the Weiv product model. If users can hit a stale UI
case, Weiv should either support it through managed tracking and region mapping
or explain why it is outside the model.

## Things We Are Not Naming As The Core Model

These concepts influenced the design but are not the default author-facing Weiv
vocabulary:

- signal
- ref
- proxy
- effect
- virtual DOM
- runtime subscription graph

We may use these internally for comparison, but Weiv's core terms should remain:
observation point, binding, region, dependency, dirty binding, owned boundary,
flush, and patch.
