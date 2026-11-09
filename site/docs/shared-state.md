# Shared State

Local and shared state use the same tracking and scheduling mechanism. Their
ownership and lifetimes differ: shared state can outlive a component, and each
component owns its subscriptions.

::: info Source and release status
This describes the managed default in the current Weiv source. Published packages
need a matching compiler/runtime release to provide it. Updating this site does
not publish new packages.
:::

## Managed project state

Within a CLI app or Vite/Bun managed project, export ordinary supported data:

```ts
// state/counter.ts
export const counter = { value: 0, label: "Shared counter" };
export function increment() { counter.value++; }
```

```html
<template>
  <p>{{ counter.label }}: {{ counter.value }}</p>
  <button @click="increment">Add</button>
</template>
<script lang="ts">
  import { counter, increment } from "./state/counter.ts";
</script>
```

The build transforms selected declarations once per canonical module. Components
and normal JS/TS consumers share identity, initialization and native live exports.
Supported writes notify regardless of callback origin. Destroying one component
releases its subscriptions without destroying shared data.

## Ownership boundary

- `emit app`/`compile` manage modules under the root component's folder.
- Vite/Bun plugins manage the discovered project graph; `root` widens the boundary
  and `components` supplies extra component roots for custom loaders.
- Standalone `emit js` manages local state and warns about unowned imported data.
- Libraries in `node_modules` and modules outside the managed root keep explicit
  observable/adapter contracts. Parsing them does not grant ownership.

See [Bundling](./bundling.md) for configuration and loading limits.

## Explicit external observables

Use `weiv:observable` for mutable data outside the managed boundary:

```ts
import { observable } from "weiv:observable";
export const counter = observable({ value: 0 });
```

Components consume recognized imported observables automatically. For a library
that retains and mutates raw references, subscribe to its notifications and copy
changes into supported observable state. Wrapping an object cannot intercept
writes through a pre-existing raw reference.

Supported mutable values are primitives, plain/null-prototype records and arrays.
Use adapters for native/class objects or accessors, and `snapshot()` for detached
immutable data. See [Runtime API](./runtime-api.md) for validation and compatibility.

## Timing and replacement

Writes are immediate; DOM patches are microtask-batched for local and shared
state alike. Supported replacement detaches the old graph from that state binding;
scalar captures retain ordinary JavaScript snapshot semantics. See
[Runtime Scheduling](./runtime-scheduling.md) and [Reactivity](./reactivity.md).
