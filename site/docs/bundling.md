# Bundling With Vite And Bun

The published `weivjs` package includes bundler adapters for both Vite and Bun.

::: info Source and release status
This describes the managed default in the current Weiv source. Published packages
need a matching compiler/runtime release to provide it. Updating this site does
not publish new packages.
:::

Install the package first:

```bash
npm i -D weivjs
```

## Vite

Install Vite if your app does not already use it:

```bash
npm i -D vite
```

Then add the Weiv plugin:

```ts
// vite.config.ts
import { defineConfig } from "vite";
import { weiv } from "weivjs/vite";

export default defineConfig({
  plugins: [weiv()]
});
```

After that, you can import `.weiv` files directly from your app:

```ts
import { mount } from "./App.weiv";

mount(document.getElementById("app")!, {});
```

## Bun

Use the Bun adapter when you want Bun to handle the plugin pipeline:

```ts
// build.ts
import { weiv } from "weivjs/bun";

const result = await Bun.build({
  entrypoints: ["./src/main.ts"],
  outdir: "./dist",
  target: "browser",
  plugins: [weiv()]
});
if (!result.success) throw new AggregateError(result.logs, "Build failed");
```

This keeps `.weiv` compilation inside the Bun build flow instead of requiring a
separate compile step.

## Which One To Use

- Use Vite when you want a standard dev server and browser build pipeline.
- Use Bun when your project already leans on Bun for build orchestration.
- In both cases, the adapter comes from the same `weivjs` package.

## Managed ownership and migration

Both adapters default to managed reactivity. They discover component roots through
static/literal entry imports and plan the graph together. Ordinary JS/TS consumers
resolve to the same generated shared modules as components.

| Option | Default | Purpose |
| --- | --- | --- |
| `root` | Project root (Vite); project/entry root (Bun) | Define the managed boundary, for example a monorepo root. |
| `components` | Discovered component roots | Add component files for custom loading paths; relative paths resolve from the managed root. |

```ts
weiv({ root: "../workspace", components: ["app/src/App.weiv"] })
```

Vite uses HTML/library/Rollup file entries. HTML module scripts must use `src`;
move inline module code into a source file. Bun uses its configured entrypoints.
Vite emits scoped component CSS and rebuilds/reloads the page when original managed
sources change. This milestone does not promise state-preserving fine-grained HMR.

Modules in `node_modules` or outside the root keep explicit observable/adapter
contracts. Merely parsing code or adding a component root does not establish
ownership over arbitrary library effects. Existing literal dynamic loaders in
managed JS/TS modules are supported; dynamic imports in component scripts/templates
and computed managed-module targets receive loader/adapter diagnostics.

Standalone `emit js` manages locals, while `emit app`/`compile` also manage project
modules under the root component's folder. Legacy `js-legacy`/`app-legacy`, alternate
`js-cells`/`app-cells` commands and the plugin `reactivity` option have been removed.
Use ordinary commands and omit that option. See
[Reactivity](./reactivity.md#migration-from-legacy-mode) for timing migration.
