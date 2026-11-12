# API Guide

This guide is the entry point to Weiv's public authoring surface. It covers the
component contract, managed state, optional runtime modules, CLI commands, and
bundler adapters.

::: info Source and release status
The API described here follows the current source. Check the package version and
release notes when a published release may lag behind current development.
:::

## Package surface

Install the tooling package:

```bash
npm i -D weivjs
```

The package exposes:

| Import or command | Purpose |
| --- | --- |
| `weiv` | CLI launcher |
| `weivjs/vite` | Vite plugin |
| `weivjs/bun` | Bun plugin |
| `weiv:observable` | Explicit observable runtime |
| `weiv:router` | Client-side router |

The native compiler currently supports macOS arm64. Other platforms need a
compatible compiler binary supplied through `WEIV_BINARY_PATH`.

## Component contract

A component is a `.weiv` file with up to three top-level sections:

```html
<template>
  <section>
    <h1>{{ title }}</h1>
    <button @click="increment">{{ count }}</button>
  </section>
</template>

<script lang="ts">
  let title = "Counter";
  let count = 0;

  function increment() {
    count += 1;
  }
</script>

<style>
  section {
    display: grid;
    gap: 0.75rem;
  }
</style>
```

The compiler owns template analysis, state dependency tracking, scoped CSS, and
the generated component module.

### Template directives

| Syntax | Meaning |
| --- | --- |
| `{{ expression }}` | Interpolate text |
| `:property="expression"` | Bind an attribute or child prop |
| `@event="handler"` | Listen for a DOM or child event |
| `#if="expression"` | Render a conditional branch |
| `#else` | Render the fallback sibling |
| `#for="item in items"` | Repeat an element or component |
| `<slot>` and `slot:name` | Compose default or named content |

See [Template Syntax](./template-syntax.md) for examples and
[Terminology](./terminology.md) for the compiler vocabulary.

### Props

Declare the input object in the component script:

```html
<script lang="ts">
  export interface Props {
    title: string;
    count: number;
  }

  export let props: Props;
</script>
```

Pass props from a parent with `:`:

```html
<CounterCard :title="heading" :count="total" />
```

### Events

Declare an event shape and call the provided `emit` binding:

```html
<script lang="ts">
  export interface Emits {
    save: { id: number };
    cancel: null;
  }

  function save() {
    emit("save", { id: 1 });
  }
</script>
```

Listen in the parent:

```html
<Editor @save="handleSave" @cancel="closeEditor" />
```

Do not declare or shadow `emit`; it belongs to the component contract. See
[Props And Emits](./props-and-emits.md) for complete examples.

## Managed state

Supported local state becomes reactive without refs, signals, or explicit
effects:

```html
<script lang="ts">
  let count = 0;

  window.addEventListener("advance", () => {
    count += 1;
  });
</script>
```

Supported mutable data includes primitive values, plain or null-prototype
records, and arrays. Use `let` or `const` for declarations. Native and class
instances, accessors, read-only descriptors, and non-extensible mutable data need
an explicit adapter or immutable snapshot.

State writes are immediate. DOM patches are queued into a microtask, so wait for
that batch before reading updated DOM or layout after a write.

The CLI app builder and bundler plugins manage supported shared project modules
as well as component-local state. Standalone `emit js` manages locals but does
not take ownership of arbitrary imported modules.

See [Reactivity](./reactivity.md),
[Shared State](./shared-state.md), and
[Runtime Scheduling](./runtime-scheduling.md).

## Observable API

Import the explicit external-state boundary from `weiv:observable`:

```ts
import { observable, snapshot, subscribe, isObservable } from "weiv:observable";

const tracked = observable({ count: 0 });
const stop = subscribe(tracked, () => {
  console.log(tracked.count);
});

tracked.count += 1;
const frozenCopy = snapshot(tracked);

stop();
console.log(isObservable(tracked));
```

| Export | Contract |
| --- | --- |
| `observable(object)` | Returns a tracked proxy for a supported object |
| `subscribe(value, listener)` | Calls the listener after a synchronized notification wave; returns a disposer |
| `snapshot(value)` | Returns a frozen plain-data copy detached from later writes |
| `isObservable(value)` | Reports whether a value belongs to this observable runtime |
| `observableBrandSymbol()` | Returns the runtime brand symbol for advanced integration |

Writes through retained raw references bypass notification. If a library mutates
its own retained object, subscribe to the library and transfer the change into
supported observable state. Dispose subscriptions when their lifetime ends.

## Router API

Create a router with file or hash history:

```ts
import { createRouter } from "weiv:router";

const router = createRouter({
  mode: "history",
  routes: [
    { path: "/", component: () => Home },
    {
      path: "/users/:id",
      component: () => Profile,
      props: (route) => ({ userId: route.params.id }),
    },
    {
      path: "/dashboard",
      component: () => Dashboard,
      children: [
        { path: "/overview", component: () => Overview },
      ],
    },
  ],
  target: document.getElementById("app")!,
});

await router.ready;
```

Route definitions support:

| Field | Purpose |
| --- | --- |
| `path` | Static path, `:param`, or `*` wildcard |
| `component` | Component module loader; may return a promise |
| `props(route)` | Derive child props from route state |
| `children` | Nested route definitions |
| `beforeEnter(ctx)` | Run before entering this route |
| `beforeLeave(ctx)` | Run before leaving this route |

Guards may return `void` to allow, `false` to block, or a string to redirect.
They may be asynchronous.

The router instance provides:

| Member | Purpose |
| --- | --- |
| `route` | Observable state with `path`, `params`, `query`, and `matched` |
| `ready` | Promise that resolves after the initial route mounts |
| `push(path)` | Navigate and add a history entry |
| `replace(path)` | Navigate and replace the current history entry |
| `back()` | Go back in history |
| `forward()` | Go forward in history |
| `beforeEach(guard)` | Add a global guard; returns a disposer |
| `afterEach(hook)` | Add a completion hook; returns a disposer |
| `destroy()` | Remove listeners and unmount routed components |

Router options also accept `base` and `scrollBehavior`. Internal links are
intercepted; external links, modified clicks, `_blank`, and downloads keep their
normal browser behavior.

See [Router Example](./router-example.md) and
[Runtime API](./runtime-api.md) for a fuller route example.

## CLI

Run the CLI from the installed package:

```bash
npx weiv --help
```

Common development commands:

```bash
# Develop one root component
npx weiv dev src/App.weiv

# Build a static app bundle; dist is the default output
npx weiv compile src/App.weiv

# Emit the JavaScript module for one component
npx weiv emit js src/App.weiv

# Emit scoped component CSS
npx weiv emit css src/App.weiv

# Validate the complete app graph
npx weiv validate app src/App.weiv --json
```

Inspection commands expose compiler representations:

```bash
npx weiv analyze script src/App.weiv
npx weiv analyze component src/App.weiv --json
npx weiv emit ast src/App.weiv
npx weiv emit sir src/App.weiv
npx weiv emit lir src/App.weiv
npx weiv emit render-tree src/App.weiv
npx weiv emit invalidation-graph src/App.weiv
```

Each `emit` command writes to standard output by default. Add an output path as
the final argument to write a file.

Prefix a command with `--json-diagnostics` for machine-readable diagnostics:

```bash
npx weiv --json-diagnostics emit js src/App.weiv
```

The JSON result includes the action, source path, success flag, and diagnostics
with codes, severity, stage, message, location, span, and fatal status.

## Vite plugin

```ts
// vite.config.ts
import { defineConfig } from "vite";
import { weiv } from "weivjs/vite";

export default defineConfig({
  plugins: [weiv()],
});
```

Options:

| Option | Default | Purpose |
| --- | --- | --- |
| `root` | Vite project root | Set the managed JavaScript and TypeScript boundary |
| `components` | Discovered components | Add component roots used by custom entry loaders |

Vite uses HTML, library, or Rollup file entries. HTML module scripts must use
`src`; inline module entry code is outside the managed-entry contract.

## Bun plugin

```ts
import { weiv } from "weivjs/bun";

const result = await Bun.build({
  entrypoints: ["./src/main.ts"],
  outdir: "./dist",
  target: "browser",
  plugins: [weiv()],
});

if (!result.success) {
  throw new AggregateError(result.logs, "Build failed");
}
```

Bun derives component roots from its entry points by default. The plugin accepts
the same `root` and `components` options as the Vite adapter.

## Integration boundaries

- Use managed local state inside `.weiv` components.
- Use project shared modules when several routes or ordinary modules need the
  same state.
- Use `observable()` or a subscription adapter for external mutable state.
- Keep unsupported native or library objects behind an adapter.
- Use matching compiler and runtime versions; graph metadata is version-sensitive.
- Treat diagnostics as part of the API when moving mutable data across the
  managed boundary.

For the system-level view, continue to [Core Architecture](./core-architecture.md).
