# Reactivity

Supported template-dependent local and project shared state are reactive
automatically inside Weiv's managed compilation boundary. Both use the same
observable tracking and scheduling core. External mutable state needs a known
observable or subscription contract.

::: info Source and release status
This describes the managed default in the current Weiv source. Published packages
need a matching compiler/runtime release to provide it. Updating this site does
not publish new packages.
:::

## Local state

Write ordinary `let`/`const` bindings and functions:

```html
<template>
  <p>{{ count }} / {{ doubled() }}</p>
  <button @click="increment">Increment</button>
</template>
<script lang="ts">
  let count = 0;
  function increment() { count++; }
  function doubled() { return count * 2; }
  window.addEventListener("advance", () => { count++; });
</script>
```

Supported writes notify from template handlers, timers, Promises and external
callbacks. They do not need `weivUpdate()` wrappers merely because the callback
comes from outside Weiv.

## Timing

Initial mounting is synchronous. State writes are immediate in JavaScript;
subsequent state-driven DOM patches are batched into microtasks. Several changes
can merge into one pending component update. See [Runtime Scheduling](./runtime-scheduling.md)
before reading DOM or layout immediately after a mutation.

## Supported data and boundaries

The mutable-data contract covers primitive values, plain/null-prototype records
and arrays. Use `let`/`const`, not `var`, for managed state. Native/class instances,
accessors, read-only data descriptors and non-extensible mutable data need an
explicit adapter or immutable `snapshot()`. Execution-only native objects can
remain raw without becoming reactive data.

The compiler diagnoses unsupported or uncertain declarations, operations, effects
and ownership. Follow the source location and suggested boundary. Parsing a module
alone does not establish ownership, and absence of warnings does not imply that
all JavaScript behavior is observable.

## Project shared state

The CLI app builder and Vite/Bun plugins transform supported project modules
alongside components. Export ordinary state:

```ts
// state/counter.ts
export const counter = { value: 0 };
export function increment() { counter.value++; }
```

Components and ordinary JS/TS consumers use the same canonical module and native
live exports. Standalone `emit js` manages local state but does not take ownership
of arbitrary imports. See [Shared State](./shared-state.md) and
[Bundling](./bundling.md) for project boundaries.

## External mutable state

Explicit `observable()` establishes the boundary for unmanaged data:

```ts
import { observable } from "weiv:observable";
const raw = library.getState();
const tracked = observable(raw);
raw.count++;     // A retained raw reference bypasses notification.
tracked.count++; // Writes through the observable notify subscribers.
```

If a library mutates its retained raw object, subscribe to the library and transfer
changes into supported observable data. Wrapping a result cannot intercept old raw
references. Dispose subscriptions when their lifetime ends.

Known constants and proven pure helpers need no blanket reactivity warning.
External mutable or uncertain template dependencies receive actionable diagnostics.

## Migration from legacy mode

Legacy reactivity and compatibility shims have been removed from current source.
Migrate by:

1. Replace `js-legacy`/`app-legacy` and `js-cells`/`app-cells` commands with ordinary
   `emit js`/`emit app` commands.
2. Remove the plugin `reactivity` option. Managed reactivity is the only model.
3. Remove `weivUpdate(callback)` calls and run the callback bodies directly.
   The helper is no longer injected or reserved.
4. Wait for the queued DOM batch before reading updated DOM or layout.
5. Use compiler diagnostics and explicit observable/subscription boundaries for
   unsupported or external mutable data.

This is a breaking source change. Use matching compiler/runtime packages; site
publication does not publish a package release. There is no legacy fallback or
synchronous callback-boundary update path.
