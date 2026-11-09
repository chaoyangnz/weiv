# Runtime Scheduling

The managed default uses one observable notification and scheduling core for
local state, managed project shared state and compatible explicit observables.

::: info Source and release status
This describes the managed default in the current Weiv source. Published packages
need a matching compiler/runtime release to provide it. Updating this site does
not publish new packages.
:::

## State now, DOM in a microtask

Initial mount creates the DOM synchronously. After mounting:

1. A supported write changes the JavaScript value immediately.
2. The reactive core queues notification work in a microtask.
3. Changed dependency keys merge into each component's pending update.
4. Compiled region code patches the affected DOM during delivery.

```ts
count++;
// State is current; DOM still represents the previous batch.
await new Promise(resolve => queueMicrotask(resolve));
// This queued batch has patched the DOM.
```

A batch executes synchronously once delivery begins. The state-driven update is
asynchronous relative to the write. Callback origin does not change this timing:
template events, timers, Promises and external callbacks use the same mechanism.

Writes during delivery can queue another wave. Waiting for one microtask is not
a promise that arbitrary chains of subsequent writes have all settled. No public
synchronous flush API is introduced by this model.

## Batching and component scope

Repeated writes can merge into one pending job per component. Each component
keeps its compiled dependency/region graph; a shared value can notify multiple
components without requiring a framework-wide virtual DOM render.

Correctness must not depend on parent-before-child, child-before-parent or sibling
update order. There is no public cross-component topological ordering guarantee.

## Lifetime and errors

Each instance owns its subscriptions. Destroying it releases them and cancels its
pending job, while shared data remains alive for other consumers. Replacing local
or shared state detaches old graphs according to the supported alias contract.

Preparation, notification and job failures do not starve independent queued work.
The default reporter uses `globalThis.reportError` when available, otherwise
reports an aggregate error in a later microtask.

## Tracking boundary

Supported managed declarations and writes notify through cells and the common
observable graph. Explicit observables notify only for writes through tracked
values. Retained external raw references stay raw; use a subscription adapter
when a library owns those writes.

See [Reactivity](./reactivity.md) for the bounded data/effect contract and
[Shared State](./shared-state.md) for module ownership.

## Legacy migration

Legacy selection, owned-boundary snapshots, callback/timer wrappers and the private
observable listener bridge have been removed. Only managed scheduling remains.

The injected `weivUpdate` helper is also removed. Run callback bodies directly and
wait for the queued batch before reading updated DOM or layout. Retired CLI modes
and the plugin `reactivity` option now reject. See
[migration guidance](./reactivity.md#migration-from-legacy-mode).
