# Weiv Status

## Current source

Weiv is a pre-v1 compiler-first frontend framework with direct DOM output.
The current source uses bounded managed reactivity as its only model for CLI component
and app emission, the development server, and Vite/Bun plugins.

::: info Source and release status
This describes the managed default in the current Weiv source. Published packages
need a matching compiler/runtime release to provide it. Updating this site does
not publish new packages.
:::

## Managed reactivity

- Supported template-dependent local state updates automatically, including writes
  from external callbacks, timers and Promises.
- CLI app and bundler builds manage supported project modules once per canonical
  module, preserving shared identity and native live/public exports.
- Local/shared state and explicit observables use a common tracking/scheduling core.
- State writes are immediate; subsequent state-driven DOM patches are microtask-batched.
- External mutable/uncertain dependencies have observable/adapter boundaries and
  source-located diagnostics. This is a bounded contract, not universal JavaScript inference.
- Legacy commands, alternate mode aliases, plugin selection and `weivUpdate`
  injection have been removed. Consumers must migrate to the managed model.

Read [Reactivity](./reactivity.md), [Shared State](./shared-state.md),
[Runtime Scheduling](./runtime-scheduling.md) and [Bundling](./bundling.md).

## Browser and component features

The working browser path includes:

- `.weiv` parsing, TypeScript script analysis and template binding
- target-neutral lowering, browser render trees and scoped CSS
- direct create/update/destroy functions with selective region updates
- component props and emits, conditionals, loops, children and slots
- default/named slots, fallback/projected switching and nested slot trees
- app bundles, module import rewriting and bundler adapters
- inspectable invalidation graphs and structured JSON diagnostics
- a client-side router with nested routes, guards, link interception, scroll
  restoration, lazy component loading and observable route state

## Verification checkpoint

The legacy-retirement checkpoint passed:

- Zig 0.16.0 build and compiler tests
- 49 Rust parser/backend tests
- 170 component/runtime/inspection/UI-core tests with 1,376 assertions
- the 204-operation/context mounted reactivity matrix
- all 14 sequential package/plugin checks
- actual default CLI/Vite/Bun shared-state builds, retired-mode rejection,
  packaged CLI invocation outside the checkout and Vite development graph reloads
- unchanged TodoMVC source under the default app builder

Kanib provides the larger routed app verification track. TodoMVC remains a smaller
app-scale example. This checkpoint does not establish production readiness or a
performance improvement; no performance benchmark was added for default adoption.

## Boundaries and next work

Supported mutable data covers primitives, plain/null-prototype records and arrays.
Native/class instances, accessors, read-only descriptors and non-extensible mutable
data need an adapter or immutable snapshot. External raw aliases remain raw.

Computed managed-module imports and dynamic imports in component scripts/templates
are outside this milestone. Existing literal loaders in managed JS/TS modules are
retained. Unknown effects, protocols and ownership keep conservative diagnostics.
See [Bundling](./bundling.md) for entry discovery and custom loader configuration.

Vite development changes rebuild the managed graph and reload the page; state-
preserving fine-grained HMR is not promised. Some dependency guards remain
conservative, and diagnostics/tooling can still improve.

Next steps are matching compiler/runtime distribution, maintained application
migration after legacy retirement. Expanding to every JavaScript case is
not a prerequisite for those steps.
