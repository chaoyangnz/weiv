# Runtime API

Weiv keeps the default runtime surface small.

Today the public runtime helpers are focused on two areas:

- explicit external observable state
- client-side routing

The managed default uses this reactive core internally for local and project
shared state without requiring public observable imports. See [Reactivity](./reactivity.md)
for the supported contract and source/release status.

## Observable

File: `packages/weiv/src/runtime/observable.ts`

Public surface:

- `observable(value)` creates a tracked proxy object
- `subscribe(observableValue, listener)` listens for changes
- `snapshot(observableValue)` returns a frozen plain-object copy
- `isObservable(value)` checks whether a value is observable
- `observableBrandSymbol()` exposes the internal brand symbol

Semantics:

- parent links are registered before exposure, including for unread nested aliases
- repeated reads return stable nested proxy identities
- sync writes are batched into one microtask notification wave
- nested writes notify both the nested node and its parent chain
- replacing or deleting a nested object detaches the old child from the former
  parent chain
- `snapshot()` returns a frozen plain-object view detached from later writes

Supported mutable values are plain/null-prototype records and arrays, with
primitive values stored in their fields. Native/class instances, accessors,
read-only descriptors and non-extensible mutable objects reject intentionally.
Use `snapshot()` for detached immutable plain data. Callable references remain
passive: their closures and properties are not made reactive by storage.

Writes through retained raw references bypass notifications. When a library owns
raw writes, subscribe to its notifications and transfer changes into supported
observable state. Compatible runtime copies in one realm share graph identity and
the scheduler; incompatible versions/realms need an explicit transfer or adapter.
Use matching compiler/runtime packages.

## Router

File: `packages/weiv/src/runtime/router.ts`

### Usage

```typescript
import { createRouter } from "weiv:router";

const router = createRouter({
  mode: "history",
  base: "",
  routes: [
    { path: "/", component: () => HomeModule },
    {
      path: "/users/:id",
      component: () => UserModule,
      props: (route) => ({ userId: route.params.id }),
    },
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
  scrollBehavior: ({ from, to }, savedPosition) =>
    savedPosition ?? { x: 0, y: 0 },
});

await router.ready;
```

### API

| Method / Property | Description |
| --- | --- |
| `router.route` | Observable route state with `path`, `params`, `query`, and `matched` |
| `router.ready` | Promise that resolves after the initial route mounts |
| `router.push(path)` | Navigate to a path and add a history entry |
| `router.replace(path)` | Navigate to a path and replace the current history entry |
| `router.back()` | Go back in history |
| `router.forward()` | Go forward in history |
| `router.beforeEach(guard)` | Add a global navigation guard |
| `router.afterEach(hook)` | Add a post-navigation hook |
| `router.destroy()` | Remove listeners and unmount components |

### Features

- static, dynamic, and wildcard route matching
- nested routes with merged params
- async global and per-route navigation guards
- internal link interception for normal in-app navigation
- lazy-loaded route components
- scroll restoration hooks
- observable route state
- history and hash routing modes

## Integration

Generated components connect managed local/shared cells and recognized imported
observables to instance-owned subscriptions. State writes are immediate; later DOM
patches are microtask-batched. Destroying an instance cancels its queued work and
releases subscriptions without destroying shared state. See
[Runtime Scheduling](./runtime-scheduling.md).

The router works with component modules that export
`mountIntoBoundary(start, end, props)`.
