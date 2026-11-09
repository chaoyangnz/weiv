# Router Example

Use `weiv:router` when your app needs client-side navigation between views.

## Create A Router

```ts
import { createRouter } from "weiv:router";

export const router = createRouter({
  mode: "history",
  routes: [
    { path: "/", component: () => import("./views/Home.mjs") },
    { path: "/about", component: () => import("./views/About.mjs") },
    {
      path: "/users/:id",
      component: () => import("./views/UserDetail.mjs"),
      props: (route) => ({ userId: route.params.id })
    }
  ],
  target: document.getElementById("app")!
});
```

## Define A Simple View

```html
<template>
  <section>
    <h1>Home</h1>
    <a href="/about">About</a>
  </section>
</template>
```

## What You Get

- history or hash routing modes
- route params
- nested routes
- navigation guards
- observable route state
- typed `weiv:router` imports from the published `weivjs` package

## Next Step

Use [Runtime API](./runtime-api.md) for the full router API surface.
