# Weiv Runtime

This folder holds the standalone shared runtime modules for Weiv.

## Observable (`observable.ts`)

Proxy-based reactive state with parent-chain propagation and microtask batching.

Public surface:

- `observable(value)` — create a tracked proxy object
- `subscribe(observableValue, listener)` — listen for changes
- `snapshot(value)` — frozen, detached plain-data view
- `isObservable(value)` — recognize a compatible runtime graph
- `observableBrandSymbol()` — internal brand symbol

Semantics:

- initial and replacement parent links are registered before the graph is exposed,
  so aliases can notify parents that have not read their children yet
- repeated reads return stable nested proxy identities
- sync writes across observable roots share one microtask notification wave
- each subscription has an independent lifetime, even when callbacks are identical
- listener membership is captured before a wave; disposed registrations are skipped
- listener writes notify in a subsequent wave; failures do not starve other listeners
- subscribers receive a set of changed property paths relative to the value
  they subscribed to; symbol-keyed writes report an unknown path (`null`)
- components importing an observable use those paths to update direct member
  bindings precisely; complex expressions still invalidate by imported binding
- nested writes notify both the nested node and its parent chain
- child-to-parent edges are weak; shared children do not retain discarded local boxes
- replacing/deleting a nested object or truncating an array detaches removed
  children, including symbol-owned and independently observable children
- writable data-property definitions and descriptor changes notify through the
  same graph; descriptor values expose tracked aliases
- failed array length reductions still report any suffix they successfully removed
- `snapshot()` returns a frozen plain-object view detached from later writes

For the timing of observable notifications versus component DOM updates, see
[Managed state timing and migration](../../README.md#state-contract-managed-reactivity-by-default).

## Internal cells (`cell.ts`)

`createModuleState()` owns private companion-module publisher slots for the
managed module transform. `getCell(name)` returns a stable slot even before
initial publication; `publish(name, value)` updates it through the common scheduler.
`afterModuleWrite()` publishes only after a successful source write and retains
its expression result. These are compiler internals. The default `emit app` build selects managed module declarations and connects publisher
subscriptions; the architecture reference defines the bounded contract.

Current source supplies internal `createCell(value)` storage and
`createCellScope(update)` subscription lifetimes. A cell is an observable record
with a `value` property: scalar writes, root replacement, and tracked nested
member writes use the existing observable graph and the shared scheduler. Existing
observables retain proxy identity when used as initial or replacement values.
The cell establishes its root parent edge before any consumer reads it.

A scope watches cells by dependency key, merges notifications into one owner job,
and passes the changed keys to its update callback. Disposal cancels queued work
and releases subscriptions without destroying shared values. Watching through a
disposed scope throws. These APIs are internal modules, not public exports or a
new authoring syntax; ordinary compilation lowers selected local bindings to cells
by default, as tracked in the architecture repository.

Explicit snapshots produced by this runtime may be stored as immutable cell
values. Their nested objects remain unproxied and frozen. Mutating the original
source does not change the captured value; replacing the cell with a new snapshot
notifies normally. Calling `observable()` on a snapshot still rejects an attempt
to treat it as mutable state.

Callable values remain passive references: snapshotting does not copy their
closures or properties. They are outside the immutable plain-data guarantee;
unverified callable snapshot effects retain explicit boundary diagnostics.

Initial observable graphs and inserted/replacement values are validated before
wrapping or assignment. Unsupported native/class objects, frozen/non-extensible
objects, accessors, and read-only data properties receive intentional TypeErrors.
Validation does not execute accessors. Ordinary primitives and callable function
values can be stored; function internals are not tracked. Existing tracked values
reuse their nodes. Plain prototype changes notify; native/class prototypes are
rejected. Accessor/read-only definitions and freeze/seal/preventExtensions are
rejected before changing the tracked object; use `snapshot()` for immutable views.
Array length retains native numeric coercion even when conversion has side effects.
Raw-reference writes remain outside the observable boundary; validation is not an
escape-proof membrane. Arbitrary external alias inference is outside the bounded contract; use an explicit
subscription adapter when a library retains raw references.

Compatible runtime copies in one realm share versioned graph, snapshot and scheduler
registries. They preserve proxy identity and one notification queue even when
bundled independently. Unversioned/incompatible branded values are rejected by
observable/cell consumption with a runtime-compatibility error; `isObservable()`
returns false. `snapshot()` explicitly transfers their enumerable data into a
local immutable view without trusting foreign metadata. Different realms and
incompatible protocol revisions must use that transfer or an explicit adapter.

## Internal scheduling (`reactive-core.ts`)

Current source uses a shared scheduler for observable notifications. It captures
all pending root notifications before delivery, then runs queued owner jobs once
per wave. Owner jobs can be cancelled; replacing a captured job defers the new
registration to the next wave. Default component output subscribes local and shared
state through one cell scope. The deprecated legacy emitter retains its older
direct owned-boundary checks and observable bridge during migration.

Errors from preparation, delivery, and jobs are collected while independent work
continues. The default reporter sends an `AggregateError` to `globalThis.reportError`
when available, otherwise throws it in a later microtask. Observable delivery
aggregates individual subscriber errors inside that outer scheduler error.
A chain exceeding 100 consecutive waves is stopped, pending work is discarded,
and a convergence error is reported. A later independent update can use the queue
again. Custom scheduler instances support injected enqueue/report functions and
wave limits for internal tests; these are not public `weiv:observable` exports.

The architecture direction and remaining work are maintained in
[weiv-arch](../../../../../weiv-arch/docs/component-state-contract.md).

## Router (`router.ts`)

Client-side router that integrates with Weiv's `mountIntoBoundary`/`destroy`
component lifecycle.

### Usage

```typescript
import { createRouter } from "weiv:router";

const router = createRouter({
  mode: "history",       // "history" (pushState) or "hash" (#-based)
  base: "",              // optional URL base path
  routes: [
    { path: "/", component: () => HomeModule },
    { path: "/users/:id", component: () => UserModule, props: (route) => ({ userId: route.params.id }) },
    {
      path: "/dashboard",
      component: () => DashLayoutModule,
      children: [
        { path: "/overview", component: () => OverviewModule },
        { path: "/stats", component: () => StatsModule },
      ],
    },
    { path: "/lazy", component: () => import("./LazyModule.mjs") },
    { path: "/files/*", component: () => FileBrowserModule },
  ],
  target: document.getElementById("app")!,
  scrollBehavior: ({ from, to }, savedPosition) => savedPosition ?? { x: 0, y: 0 },
});

await router.ready;
```

### API

| Method / Property | Description |
|---|---|
| `router.route` | Observable `{ path, params, query, matched }` — subscribe to react to route changes |
| `router.ready` | Promise that resolves after initial route mounts |
| `router.push(path)` | Navigate to path (adds history entry) |
| `router.replace(path)` | Navigate to path (replaces current history entry) |
| `router.back()` | Go back in history |
| `router.forward()` | Go forward in history |
| `router.beforeEach(guard)` | Add global navigation guard; returns unsubscribe function |
| `router.afterEach(hook)` | Add post-navigation hook; returns unsubscribe function |
| `router.destroy()` | Remove all listeners, unmount components |

### Features

- **Route matching**: static segments, `:param` dynamic segments, `*` wildcard catch-all
- **Nested routes**: parent stays mounted while children swap; params merged across levels
- **Navigation guards**: `beforeEach` (global), `beforeEnter` (per-route), `beforeLeave` (per-route). Return `false` to block, a string to redirect, or void to allow. Async guards supported.
- **Link interception**: internal `<a>` clicks are caught and routed through `push()`. Skips external links, `target="_blank"`, modifier keys, `download`, `mailto:`/`tel:`.
- **Lazy loading**: `component` can return a Promise for code-split routes
- **Scroll restoration**: `scrollBehavior` callback receives navigation context and saved position. Supports `{ x, y }` coordinates or `{ el: "#selector" }`.
- **Observable route state**: `router.route` is an observable — any component can `subscribe()` to it
- **History and hash modes**: `mode: "history"` (pushState) or `mode: "hash"` (#-based with hashchange listener)

### Guard Types

```typescript
// Global guard — runs before every navigation
router.beforeEach(async ({ from, to }) => {
  if (to.path === "/admin" && !isAuthenticated()) return "/login";
});

// Per-route enter guard
{ path: "/admin", component: () => AdminModule, beforeEnter: ({ to }) => isAdmin() }

// Per-route leave guard (unsaved form protection)
{ path: "/editor", component: () => EditorModule, beforeLeave: () => !hasUnsavedChanges || confirm("Discard?") }
```

## Integration

Weiv component integration currently relies on the observable brand and metadata
contract directly rather than importing these helper wrappers from
`weiv:observable`. The router works with any module that exports
`mountIntoBoundary(start, end, props)`.
