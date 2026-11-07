# weivjs

Compiler-first `.weiv` tooling in one package:

- `weiv` CLI
- Vite plugin (`weivjs/vite`)
- Bun plugin (`weivjs/bun`)
- optional `weiv:*` typings (`weiv:observable`, `weiv:router`)

## Install

```bash
npm i -D weivjs
```

Then run:

```bash
npx weiv --help
```

The current source enables managed reactivity by default. Published installations
need a matching compiler/runtime release; this documentation update does not
publish packages.

## CLI Usage

```bash
# Dev server
npx weiv dev src/App.weiv

# Emit browser app bundle
npx weiv compile emit app src/App.weiv ./dist

# Emit JS for a component
npx weiv compile emit js src/App.weiv
```

## Writing `.weiv` SFCs

You can build normal components without any `weiv:*` imports.

```html
<template>
  <section>
    <h1>{{ title }}</h1>
    <p>Count: {{ count }}</p>
    <button @click="increment">Increment</button>
  </section>
</template>

<script>
  let title = "Hello Weiv";
  let count = 0;
  function increment() {
    count += 1;
  }
</script>
```

Managed project state needs no observable import. Use `weiv:observable` for explicit external integration boundaries and `weiv:router` for routing.

### State contract: managed reactivity by default

Supported template-dependent local state is reactive automatically. The CLI app
builder and Vite/Bun plugins also manage project modules, so components and normal
JavaScript consumers share one state instance with native live exports.

```html
<template><p>{{ count }}</p></template>
<script lang="ts">
  let count = 0;
  window.addEventListener("advance", () => { count++; });
</script>
```

The callback needs no `weivUpdate()` wrapper. Supported writes notify regardless
of whether they come from a template handler, timer, Promise or external callback.
Initial mounting is synchronous. Later state changes are immediate in JavaScript;
Weiv batches their DOM patches into microtasks, merging changes into one pending
update per component. Destroying a component releases subscriptions and cancels
its pending update without destroying shared state.

```js
count++;
// State is current; the DOM still represents the previous batch.
await new Promise(resolve => queueMicrotask(resolve));
// The queued batch has patched the DOM. Writes during delivery can queue another wave.
```

The supported mutable data is primitive values, ordinary plain/null-prototype
records and arrays. Use `let`/`const`, not `var`, for managed state. Native/class
instances, accessors, read-only data descriptors and non-extensible mutable data
are outside this contract; use an explicit adapter or an immutable `snapshot()`.
Execution-only native objects can remain raw without becoming reactive data.

Project ownership is explicit: the plugins discover static component imports
from their entry files and compile the graph together. Vite defaults to its project
root; Bun defaults to the project/entry root. Configure `root` for a monorepo and
`components` for additional roots used by a custom loader. Code in `node_modules`
or outside the managed root is not automatically transformed into shared state.
Known constants and pure helpers need no blanket reactivity warning.

`emit js` emits a standalone component: its local state is managed, but it does
not take ownership of arbitrary imported modules. Use the app builder or bundler
plugins for automatic project shared state. CLI app ownership starts at the root
component's folder; plugins use their project/configured root. Existing literal dynamic loaders in
managed JS/TS modules are supported; dynamic imports in component scripts/templates
and computed managed-module targets have an explicit loader/adapter diagnostic.

### External state and explicit observables

External mutable state needs a known notification contract. Weiv recognizes
explicit observables and warns at template dependencies whose ownership or update
coverage cannot be verified. Follow the diagnostic's source location and guidance
rather than assuming any imported object is reactive.

```js
const raw = library.getState();
const tracked = observable(raw);
raw.count++;     // A retained raw reference bypasses notification.
tracked.count++; // Writes through the observable notify subscribers.
```

If a library mutates its retained raw state, subscribe to that library and transfer
changes into supported observable data. Wrapping its result cannot intercept old
raw references. Dispose external subscriptions when their lifetime ends.

### Migrating from legacy reactivity

The default managed mode batches DOM updates into microtasks. Code that reads DOM
or layout immediately after a handler must wait for the batch. `weivUpdate` is no
longer injected or reserved: remove its calls and run the callback body directly.
Supported writes notify automatically. Update unsupported managed declarations/types
using the compiler's diagnostics.
Use a matching compiler/runtime version; incompatible older observable metadata
requires an explicit transfer rather than mixing graph internals.

Legacy reactivity has been retired. `js-legacy`/`app-legacy` commands and
the plugin `reactivity` option are no longer supported. Remove the option, use
ordinary `emit js`/`emit app` commands, and migrate immediate DOM reads to wait for
the batch. Alternate `js-cells`/`app-cells` commands have also been removed.

This is a breaking source change. Use matching compiler/runtime packages; the
source update does not publish a new npm release.

## Vite Plugin

```ts
// vite.config.ts
import { defineConfig } from "vite";
import { weiv } from "weivjs/vite";

export default defineConfig({
  plugins: [weiv()]
});
```

The default is managed reactivity. For custom entry loaders use `weiv({ components: ["src/App.weiv"] })`; for a wider monorepo ownership boundary set `root`. Development changes rebuild the managed graph and reload the page to preserve canonical module identity.

You can then import `.weiv` files directly in your app. The plugin emits both
the component JavaScript and its scoped `<style>` CSS through Vite.

## Bun Plugin

```ts
// build.ts — run with bun build.ts
import { weiv } from "weivjs/bun";

const result = await Bun.build({
  entrypoints: ["./src/main.ts"],
  outdir: "./dist",
  target: "browser",
  plugins: [weiv()]
});
if (!result.success) throw new AggregateError(result.logs, "Build failed");
```

Both plugins accept the same ownership and migration options:

| Option | Default | Purpose |
| --- | --- | --- |
| `root` | Project root (Vite); project/entry root (Bun) | Set the managed module boundary, for example a monorepo root. |
| `components` | Discovered component roots | Add component file paths for custom loading paths. Relative paths resolve from the managed root. |

Entry discovery follows static/literal imports. Vite HTML module scripts must use
file entries; move inline module code into a source file. Adding a component root
does not make arbitrary library internals reactive. Keep external mutable data
behind an observable or subscription adapter.

## Optional `weiv:*` Typings

This package ships optional typing support for:

- `weiv:observable`
- `weiv:router`

Use these when needed in your app or generated code.
