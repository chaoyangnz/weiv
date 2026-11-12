# Getting Started

## Status

`weiv` is runnable today, but still pre-v1. The current source package version
is `0.1.2`.

The current checkpoint includes a working direct-DOM browser path,
compiler-driven invalidation, slot composition, shared observable runtime
integration, runtime routing, and growing runtime/component verification.

## Install

```bash
npm i -D weivjs
```

The published `weivjs` package includes:

- the `weiv` CLI
- bundler adapters at `weivjs/vite` and `weivjs/bun`
- optional typings for `weiv:observable` and `weiv:router`

## Install The VS Code Extension

For the best `.weiv` authoring experience in VS Code, install the Weiv
extension too.

See [VS Code Extension](./vscode-extension.md).

## Check The CLI

```bash
npx weiv --help
```

## Run Your Own Root Component

```bash
npx weiv dev path/to/App.weiv
```

## Emit A Static App Bundle

```bash
npx weiv compile path/to/App.weiv
cd ./dist
bun server.ts
```

`compile` writes to `dist` by default. Pass an output directory when you want a
different bundle location:

```bash
npx weiv compile path/to/App.weiv ./public
```

## Diagnostics JSON

```bash
npx weiv --json-diagnostics emit js path/to/App.weiv
```

This emits structured diagnostics with:

- `action`
- `sourcePath`
- `ok`
- `diagnostics`

## Optional Runtime Imports

Use `weiv:*` imports only when you need them.

- `weiv:observable` for explicit external mutable-state boundaries
- `weiv:router` for client-side routing

The package already includes typings for both virtual modules.

For concrete examples, see [Shared State](./shared-state.md) and
[Router Example](./router-example.md).

## State model and migration

Current source enables automatic supported local and managed project shared state
by default. State writes are immediate; later DOM patches are microtask-batched.
Published installations need a matching compiler/runtime release for this default.
See [Reactivity](./reactivity.md) for boundaries and deprecated legacy migration,
and [Bundling](./bundling.md) for managed project ownership. Use the
[API Guide](./api-guide.md) for the complete public surface and
[Core Architecture](./core-architecture.md) for the compilation model.
