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
or layout immediately after a handler must wait for the batch. Existing
`weivUpdate(callback)` calls may stay: managed mode executes the callback and
preserves its value/error/Promise; the call does not force a synchronous DOM flush.
Update unsupported managed declarations/types using the compiler's diagnostics.
Use a matching compiler/runtime version; incompatible older observable metadata
requires an explicit transfer rather than mixing graph internals.

A deprecated compatibility mode is available during migration:

```sh
weiv emit js-legacy src/App.weiv
weiv emit app-legacy src/App.weiv dist
```

```js
weiv({ reactivity: "legacy" }) // Vite or Bun plugin
```

Legacy retains owned-handler synchronous checks and manual `weivUpdate` requirements
for external local mutations. New code should use the default managed mode. Legacy
will be removed in a future breaking release after application migrations; no
removal date is imposed by this change. This source change requires a matching
compiler/runtime release before it is available through a published npm update.

### DOM bindings and input state

Weiv directives always begin with a symbol:

- `:name` binds a DOM property, attribute, or component prop.
- `@event` handles a DOM or component event.
- `#if`, `#else`, and `#for` control template structure.

The older `bind:name` and `on:event` spellings are deprecated compatibility
syntax. They remain accepted for now, but new and migrated code should use the
symbol forms.

Structural directives use `#` so they cannot be confused with ordinary HTML
attributes:

```html
<label for="email">Email</label>
<article #for="item in items">
  <p #if="item.visible">{{ item.label }}</p>
  <p #else>Hidden</p>
</article>
```

Bare `if`, `else`, and `for` are ordinary attributes. This keeps native and
custom-element attributes available without special escaping.

Binding directives write component state to DOM properties and attributes; they
are one-way. In particular, `:value`/`bind:value` does not write user edits back
to the component variable. Handle the input event explicitly when component
state must track the field:

```html
<input :value="draftName" @input="updateDraftName" />

<script lang="ts">
  let draftName = "";

  function updateDraftName(event: Event) {
    draftName = (event.currentTarget as HTMLInputElement).value;
  }
</script>
```

### Global styles

Component styles are scoped by default. Wrap a whole selector in `:global(...)`
when it must apply outside the component scope:

```css
:global(:root) {
  --ink: #193047;
}

:global(body) {
  margin: 0;
}
```

Shared state example:

```ts
// state/counter.ts
// Inside the project managed by the app builder or bundler plugin:
export const counter = { value: 0 };
```

```html
<template>
  <div>
    <p>Shared: {{ counter.value }}</p>
    <button @click="counter.value += 1">Add</button>
  </div>
</template>

<script>
  import { counter } from "./state/counter.ts";
</script>
```

Router example:

```ts
import { createRouter } from "weiv:router";

export const router = createRouter({
  routes: [
    { path: "/", component: () => import("./views/Home.mjs") },
    { path: "/about", component: () => import("./views/About.mjs") }
  ],
  target: document.getElementById("app")
});
```

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
| `reactivity` | `"managed"` | Use `"legacy"` only for deprecated migration compatibility. |
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
