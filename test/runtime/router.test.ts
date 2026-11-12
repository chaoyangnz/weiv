import { expect, test, beforeEach } from "bun:test";
import { JSDOM } from "jsdom";

function setupDom() {
  const dom = new JSDOM("<!doctype html><html><body></body></html>", {
    url: "http://localhost/",
  });
  (globalThis as any).window = dom.window;
  (globalThis as any).document = dom.window.document;
  (globalThis as any).history = dom.window.history;
  (globalThis as any).location = dom.window.location;
  return dom;
}

function fakeComponent(name: string) {
  return {
    mountIntoBoundary(start: Comment, end: Comment, props: Record<string, any> = {}) {
      const el = document.createElement("div");
      el.setAttribute("data-component", name);
      el.textContent = `${name}:${JSON.stringify(props)}`;
      start.parentNode!.insertBefore(el, end);

      let currentProps = { ...props };

      return {
        instance: {},
        update: () => {
          el.textContent = `${name}:${JSON.stringify(currentProps)}`;
        },
        destroy: () => {
          el.remove();
        },
        setProps: (next: Record<string, any>) => {
          currentProps = { ...next };
        },
        start,
        end,
      };
    },
  };
}

let dom: JSDOM;

beforeEach(() => {
  dom = setupDom();
});

// --- Core Routing ---

test("mounts the matching route component", async () => {
  const { createRouter } = await import("../../packages/weiv/src/runtime/router");

  const target = document.createElement("div");
  document.body.appendChild(target);

  const router = createRouter({
    mode: "history",
    routes: [
      { path: "/", component: () => fakeComponent("Home") },
      { path: "/about", component: () => fakeComponent("About") },
    ],
    target,
  });
  await router.ready;

  expect(target.textContent).toContain("Home");
  expect(router.route.matched).toBe("/");

  router.destroy();
});

test("push navigates to a new route", async () => {
  const { createRouter } = await import("../../packages/weiv/src/runtime/router");

  const target = document.createElement("div");
  document.body.appendChild(target);

  const router = createRouter({
    mode: "history",
    routes: [
      { path: "/", component: () => fakeComponent("Home") },
      { path: "/about", component: () => fakeComponent("About") },
    ],
    target,
  });
  await router.ready;

  expect(target.textContent).toContain("Home");

  await router.push("/about");
  expect(target.textContent).toContain("About");
  expect(target.textContent).not.toContain("Home");
  expect(router.route.path).toBe("/about");
  expect(router.route.matched).toBe("/about");

  router.destroy();
});

test("extracts route params from dynamic segments", async () => {
  const { createRouter } = await import("../../packages/weiv/src/runtime/router");

  const target = document.createElement("div");
  document.body.appendChild(target);

  const router = createRouter({
    mode: "history",
    routes: [
      {
        path: "/users/:id",
        component: () => fakeComponent("User"),
        props: route => ({ userId: route.params.id }),
      },
    ],
    target,
  });
  await router.ready;

  await router.push("/users/42");
  expect(router.route.params.id).toBe("42");
  expect(target.textContent).toContain('"userId":"42"');

  router.destroy();
});

test("same pattern re-uses component instance with updated props", async () => {
  const { createRouter } = await import("../../packages/weiv/src/runtime/router");

  const target = document.createElement("div");
  document.body.appendChild(target);

  let mountCount = 0;
  const trackedComponent = {
    mountIntoBoundary(start: Comment, end: Comment, props: Record<string, any>) {
      mountCount++;
      return fakeComponent("User").mountIntoBoundary(start, end, props);
    },
  };

  const router = createRouter({
    mode: "history",
    routes: [
      {
        path: "/users/:id",
        component: () => trackedComponent,
        props: route => ({ userId: route.params.id }),
      },
    ],
    target,
  });
  await router.ready;

  await router.push("/users/1");
  expect(mountCount).toBe(1);

  await router.push("/users/2");
  expect(mountCount).toBe(1);

  router.destroy();
});

test("no matching route clears the outlet", async () => {
  const { createRouter } = await import("../../packages/weiv/src/runtime/router");

  const target = document.createElement("div");
  document.body.appendChild(target);

  const router = createRouter({
    mode: "history",
    routes: [{ path: "/", component: () => fakeComponent("Home") }],
    target,
  });
  await router.ready;

  expect(target.textContent).toContain("Home");

  await router.push("/nonexistent");
  expect(target.textContent).not.toContain("Home");
  expect(router.route.matched).toBeNull();

  router.destroy();
});

test("replace does not add a history entry", async () => {
  const { createRouter } = await import("../../packages/weiv/src/runtime/router");

  const target = document.createElement("div");
  document.body.appendChild(target);

  const router = createRouter({
    mode: "history",
    routes: [
      { path: "/", component: () => fakeComponent("Home") },
      { path: "/about", component: () => fakeComponent("About") },
    ],
    target,
  });
  await router.ready;

  await router.replace("/about");
  expect(target.textContent).toContain("About");
  expect(router.route.path).toBe("/about");

  router.destroy();
});

test("parses query parameters", async () => {
  const { createRouter } = await import("../../packages/weiv/src/runtime/router");

  const target = document.createElement("div");
  document.body.appendChild(target);

  const router = createRouter({
    mode: "history",
    routes: [{ path: "/search", component: () => fakeComponent("Search") }],
    target,
  });
  await router.ready;

  await router.push("/search?q=hello&page=2");
  expect(router.route.query.q).toBe("hello");
  expect(router.route.query.page).toBe("2");

  router.destroy();
});

test("wildcard route captures remainder", async () => {
  const { createRouter } = await import("../../packages/weiv/src/runtime/router");

  const target = document.createElement("div");
  document.body.appendChild(target);

  const router = createRouter({
    mode: "history",
    routes: [{ path: "/files/*", component: () => fakeComponent("Files") }],
    target,
  });
  await router.ready;

  await router.push("/files/docs/readme.md");
  expect(router.route.params["*"]).toBe("docs/readme.md");

  router.destroy();
});

test("route state is observable", async () => {
  const { createRouter } = await import("../../packages/weiv/src/runtime/router");
  const { subscribe } = await import("../../packages/weiv/src/runtime/observable");

  const target = document.createElement("div");
  document.body.appendChild(target);

  const router = createRouter({
    mode: "history",
    routes: [
      { path: "/", component: () => fakeComponent("Home") },
      { path: "/about", component: () => fakeComponent("About") },
    ],
    target,
  });
  await router.ready;

  let notified = 0;
  const unsub = subscribe(router.route, () => {
    notified++;
  });

  await router.push("/about");
  await new Promise(resolve => queueMicrotask(resolve));
  expect(notified).toBe(1);

  unsub();
  router.destroy();
});

test("async component loading", async () => {
  const { createRouter } = await import("../../packages/weiv/src/runtime/router");

  const target = document.createElement("div");
  document.body.appendChild(target);

  const router = createRouter({
    mode: "history",
    routes: [
      {
        path: "/lazy",
        component: () => Promise.resolve(fakeComponent("LazyPage")),
      },
    ],
    target,
  });
  await router.ready;

  await router.push("/lazy");
  expect(target.textContent).toContain("LazyPage");

  router.destroy();
});

test("destroy cleans up listeners and mounted component", async () => {
  const { createRouter } = await import("../../packages/weiv/src/runtime/router");

  const target = document.createElement("div");
  document.body.appendChild(target);

  const router = createRouter({
    mode: "history",
    routes: [{ path: "/", component: () => fakeComponent("Home") }],
    target,
  });
  await router.ready;

  expect(target.textContent).toContain("Home");

  router.destroy();

  const divs = target.querySelectorAll("[data-component]");
  expect(divs.length).toBe(0);
});

test("multiple params in path", async () => {
  const { createRouter } = await import("../../packages/weiv/src/runtime/router");

  const target = document.createElement("div");
  document.body.appendChild(target);

  const router = createRouter({
    mode: "history",
    routes: [
      {
        path: "/orgs/:orgId/users/:userId",
        component: () => fakeComponent("OrgUser"),
        props: route => ({ org: route.params.orgId, user: route.params.userId }),
      },
    ],
    target,
  });
  await router.ready;

  await router.push("/orgs/acme/users/42");
  expect(router.route.params.orgId).toBe("acme");
  expect(router.route.params.userId).toBe("42");
  expect(target.textContent).toContain('"org":"acme"');
  expect(target.textContent).toContain('"user":"42"');

  router.destroy();
});

// --- Link Interception ---

test("clicking an internal link navigates via router", async () => {
  const { createRouter } = await import("../../packages/weiv/src/runtime/router");

  const target = document.createElement("div");
  document.body.appendChild(target);

  const router = createRouter({
    mode: "history",
    routes: [
      { path: "/", component: () => fakeComponent("Home") },
      { path: "/about", component: () => fakeComponent("About") },
    ],
    target,
  });
  await router.ready;

  const link = document.createElement("a");
  link.setAttribute("href", "/about");
  document.body.appendChild(link);

  const event = new dom.window.MouseEvent("click", {
    bubbles: true,
    cancelable: true,
    button: 0,
  });
  link.dispatchEvent(event);

  expect(event.defaultPrevented).toBe(true);
  await new Promise(resolve => setTimeout(resolve, 10));
  expect(target.textContent).toContain("About");
  expect(router.route.path).toBe("/about");

  link.remove();
  router.destroy();
});

test("clicking a link with target=_blank is not intercepted", async () => {
  const { createRouter } = await import("../../packages/weiv/src/runtime/router");

  const target = document.createElement("div");
  document.body.appendChild(target);

  const router = createRouter({
    mode: "history",
    routes: [
      { path: "/", component: () => fakeComponent("Home") },
      { path: "/about", component: () => fakeComponent("About") },
    ],
    target,
  });
  await router.ready;

  const link = document.createElement("a");
  link.setAttribute("href", "/about");
  link.setAttribute("target", "_blank");
  document.body.appendChild(link);

  const event = new dom.window.MouseEvent("click", {
    bubbles: true,
    cancelable: true,
    button: 0,
  });
  link.dispatchEvent(event);

  expect(event.defaultPrevented).toBe(false);
  expect(target.textContent).toContain("Home");

  link.remove();
  router.destroy();
});

test("clicking an external link is not intercepted", async () => {
  const { createRouter } = await import("../../packages/weiv/src/runtime/router");

  const target = document.createElement("div");
  document.body.appendChild(target);

  const router = createRouter({
    mode: "history",
    routes: [{ path: "/", component: () => fakeComponent("Home") }],
    target,
  });
  await router.ready;

  const link = document.createElement("a");
  link.setAttribute("href", "https://example.com/page");
  document.body.appendChild(link);

  const event = new dom.window.MouseEvent("click", {
    bubbles: true,
    cancelable: true,
    button: 0,
  });
  link.dispatchEvent(event);

  expect(event.defaultPrevented).toBe(false);

  link.remove();
  router.destroy();
});

test("ctrl+click on a link is not intercepted", async () => {
  const { createRouter } = await import("../../packages/weiv/src/runtime/router");

  const target = document.createElement("div");
  document.body.appendChild(target);

  const router = createRouter({
    mode: "history",
    routes: [
      { path: "/", component: () => fakeComponent("Home") },
      { path: "/about", component: () => fakeComponent("About") },
    ],
    target,
  });
  await router.ready;

  const link = document.createElement("a");
  link.setAttribute("href", "/about");
  document.body.appendChild(link);

  const event = new dom.window.MouseEvent("click", {
    bubbles: true,
    cancelable: true,
    button: 0,
    ctrlKey: true,
  });
  link.dispatchEvent(event);

  expect(event.defaultPrevented).toBe(false);
  expect(target.textContent).toContain("Home");

  link.remove();
  router.destroy();
});

// --- Navigation Guards ---

test("beforeEach guard blocks navigation when returning false", async () => {
  const { createRouter } = await import("../../packages/weiv/src/runtime/router");

  const target = document.createElement("div");
  document.body.appendChild(target);

  const router = createRouter({
    mode: "history",
    routes: [
      { path: "/", component: () => fakeComponent("Home") },
      { path: "/secret", component: () => fakeComponent("Secret") },
    ],
    target,
  });
  await router.ready;

  router.beforeEach(({ to }) => {
    if (to.path === "/secret") return false;
  });

  await router.push("/secret");

  expect(target.textContent).toContain("Home");
  expect(target.textContent).not.toContain("Secret");
  expect(router.route.path).toBe("/");

  router.destroy();
});

test("beforeEach guard redirects when returning a string", async () => {
  const { createRouter } = await import("../../packages/weiv/src/runtime/router");

  const target = document.createElement("div");
  document.body.appendChild(target);

  const router = createRouter({
    mode: "history",
    routes: [
      { path: "/", component: () => fakeComponent("Home") },
      { path: "/login", component: () => fakeComponent("Login") },
      { path: "/dashboard", component: () => fakeComponent("Dashboard") },
    ],
    target,
  });
  await router.ready;

  router.beforeEach(({ to }) => {
    if (to.path === "/dashboard") return "/login";
  });

  await router.push("/dashboard");

  expect(target.textContent).toContain("Login");
  expect(router.route.path).toBe("/login");

  router.destroy();
});

test("beforeEach guard allows navigation when returning void", async () => {
  const { createRouter } = await import("../../packages/weiv/src/runtime/router");

  const target = document.createElement("div");
  document.body.appendChild(target);

  let guardCalled = false;
  const router = createRouter({
    mode: "history",
    routes: [
      { path: "/", component: () => fakeComponent("Home") },
      { path: "/about", component: () => fakeComponent("About") },
    ],
    target,
  });
  await router.ready;

  router.beforeEach(() => {
    guardCalled = true;
  });

  await router.push("/about");

  expect(guardCalled).toBe(true);
  expect(target.textContent).toContain("About");

  router.destroy();
});

test("async beforeEach guard works", async () => {
  const { createRouter } = await import("../../packages/weiv/src/runtime/router");

  const target = document.createElement("div");
  document.body.appendChild(target);

  const router = createRouter({
    mode: "history",
    routes: [
      { path: "/", component: () => fakeComponent("Home") },
      { path: "/slow", component: () => fakeComponent("Slow") },
    ],
    target,
  });
  await router.ready;

  router.beforeEach(async () => {
    await new Promise(resolve => setTimeout(resolve, 5));
    return false;
  });

  await router.push("/slow");

  expect(target.textContent).toContain("Home");

  router.destroy();
});

test("per-route beforeEnter guard", async () => {
  const { createRouter } = await import("../../packages/weiv/src/runtime/router");

  const target = document.createElement("div");
  document.body.appendChild(target);

  const router = createRouter({
    mode: "history",
    routes: [
      { path: "/", component: () => fakeComponent("Home") },
      {
        path: "/admin",
        component: () => fakeComponent("Admin"),
        beforeEnter: () => false,
      },
      { path: "/public", component: () => fakeComponent("Public") },
    ],
    target,
  });
  await router.ready;

  await router.push("/admin");
  expect(target.textContent).toContain("Home");

  await router.push("/public");
  expect(target.textContent).toContain("Public");

  router.destroy();
});

test("per-route beforeLeave guard", async () => {
  const { createRouter } = await import("../../packages/weiv/src/runtime/router");

  const target = document.createElement("div");
  document.body.appendChild(target);

  let allowLeave = false;
  const router = createRouter({
    mode: "history",
    routes: [
      { path: "/", component: () => fakeComponent("Home") },
      {
        path: "/editor",
        component: () => fakeComponent("Editor"),
        beforeLeave: () => allowLeave,
      },
      { path: "/other", component: () => fakeComponent("Other") },
    ],
    target,
  });
  await router.ready;

  await router.push("/editor");
  expect(target.textContent).toContain("Editor");

  await router.push("/other");
  expect(target.textContent).toContain("Editor");

  allowLeave = true;
  await router.push("/other");
  expect(target.textContent).toContain("Other");

  router.destroy();
});

test("unsubscribing a beforeEach guard removes it", async () => {
  const { createRouter } = await import("../../packages/weiv/src/runtime/router");

  const target = document.createElement("div");
  document.body.appendChild(target);

  const router = createRouter({
    mode: "history",
    routes: [
      { path: "/", component: () => fakeComponent("Home") },
      { path: "/about", component: () => fakeComponent("About") },
    ],
    target,
  });
  await router.ready;

  const unsub = router.beforeEach(() => false);

  await router.push("/about");
  expect(target.textContent).toContain("Home");

  unsub();

  await router.push("/about");
  expect(target.textContent).toContain("About");

  router.destroy();
});

test("afterEach hook is called after navigation", async () => {
  const { createRouter } = await import("../../packages/weiv/src/runtime/router");

  const target = document.createElement("div");
  document.body.appendChild(target);

  const router = createRouter({
    mode: "history",
    routes: [
      { path: "/", component: () => fakeComponent("Home") },
      { path: "/about", component: () => fakeComponent("About") },
    ],
    target,
  });
  await router.ready;

  let hookFrom = "";
  let hookTo = "";
  router.afterEach(({ from, to }) => {
    hookFrom = from.path;
    hookTo = to.path;
  });

  await router.push("/about");

  expect(hookFrom).toBe("/");
  expect(hookTo).toBe("/about");

  router.destroy();
});

// --- Nested Routes ---

test("nested routes mount parent and child", async () => {
  const { createRouter } = await import("../../packages/weiv/src/runtime/router");

  const target = document.createElement("div");
  document.body.appendChild(target);

  const router = createRouter({
    mode: "history",
    routes: [
      {
        path: "/dashboard",
        component: () => fakeComponent("DashLayout"),
        children: [
          { path: "/overview", component: () => fakeComponent("Overview") },
          { path: "/stats", component: () => fakeComponent("Stats") },
        ],
      },
    ],
    target,
  });
  await router.ready;

  await router.push("/dashboard/overview");

  expect(target.textContent).toContain("DashLayout");
  expect(target.textContent).toContain("Overview");

  router.destroy();
});

test("switching child routes preserves parent", async () => {
  const { createRouter } = await import("../../packages/weiv/src/runtime/router");

  const target = document.createElement("div");
  document.body.appendChild(target);

  let parentMountCount = 0;
  const trackedParent = {
    mountIntoBoundary(start: Comment, end: Comment, props: Record<string, any>) {
      parentMountCount++;
      return fakeComponent("DashLayout").mountIntoBoundary(start, end, props);
    },
  };

  const router = createRouter({
    mode: "history",
    routes: [
      {
        path: "/dashboard",
        component: () => trackedParent,
        children: [
          { path: "/overview", component: () => fakeComponent("Overview") },
          { path: "/stats", component: () => fakeComponent("Stats") },
        ],
      },
    ],
    target,
  });
  await router.ready;

  await router.push("/dashboard/overview");
  expect(parentMountCount).toBe(1);
  expect(target.textContent).toContain("Overview");

  await router.push("/dashboard/stats");
  expect(parentMountCount).toBe(1);
  expect(target.textContent).toContain("Stats");

  router.destroy();
});

test("nested route params are merged", async () => {
  const { createRouter } = await import("../../packages/weiv/src/runtime/router");

  const target = document.createElement("div");
  document.body.appendChild(target);

  const router = createRouter({
    mode: "history",
    routes: [
      {
        path: "/orgs/:orgId",
        component: () => fakeComponent("OrgLayout"),
        children: [
          {
            path: "/teams/:teamId",
            component: () => fakeComponent("Team"),
            props: route => ({ org: route.params.orgId, team: route.params.teamId }),
          },
        ],
      },
    ],
    target,
  });
  await router.ready;

  await router.push("/orgs/acme/teams/eng");

  expect(router.route.params.orgId).toBe("acme");
  expect(router.route.params.teamId).toBe("eng");
  expect(target.textContent).toContain('"org":"acme"');
  expect(target.textContent).toContain('"team":"eng"');

  router.destroy();
});

test("navigating away from nested route destroys all levels", async () => {
  const { createRouter } = await import("../../packages/weiv/src/runtime/router");

  const target = document.createElement("div");
  document.body.appendChild(target);

  const router = createRouter({
    mode: "history",
    routes: [
      { path: "/", component: () => fakeComponent("Home") },
      {
        path: "/dashboard",
        component: () => fakeComponent("DashLayout"),
        children: [{ path: "/overview", component: () => fakeComponent("Overview") }],
      },
    ],
    target,
  });
  await router.ready;

  await router.push("/dashboard/overview");
  expect(target.textContent).toContain("DashLayout");
  expect(target.textContent).toContain("Overview");

  await router.push("/");
  expect(target.textContent).toContain("Home");
  expect(target.textContent).not.toContain("DashLayout");
  expect(target.textContent).not.toContain("Overview");

  router.destroy();
});

// --- Scroll Restoration ---

test("scrollBehavior is called with navigation context", async () => {
  const { createRouter } = await import("../../packages/weiv/src/runtime/router");

  const target = document.createElement("div");
  document.body.appendChild(target);

  const scrollCalls: Array<{ from: string; to: string; saved: any }> = [];

  const router = createRouter({
    mode: "history",
    routes: [
      { path: "/", component: () => fakeComponent("Home") },
      { path: "/about", component: () => fakeComponent("About") },
      { path: "/contact", component: () => fakeComponent("Contact") },
    ],
    target,
    scrollBehavior: ({ from, to }, savedPosition) => {
      scrollCalls.push({ from: from.path, to: to.path, saved: savedPosition });
      return { x: 0, y: 0 };
    },
  });
  await router.ready;

  const initialCalls = scrollCalls.length;
  await router.push("/about");

  expect(scrollCalls.length).toBe(initialCalls + 1);
  const call = scrollCalls[scrollCalls.length - 1];
  expect(call.from).toBe("/");
  expect(call.to).toBe("/about");
  expect(call.saved).toBeNull();

  await router.push("/contact");
  expect(scrollCalls.length).toBe(initialCalls + 2);

  router.destroy();
});

test("scrollBehavior can scroll to element selector", async () => {
  const { createRouter } = await import("../../packages/weiv/src/runtime/router");

  const target = document.createElement("div");
  document.body.appendChild(target);

  const section = document.createElement("div");
  section.id = "features";
  let scrolledIntoView = false;
  section.scrollIntoView = () => {
    scrolledIntoView = true;
  };
  document.body.appendChild(section);

  const router = createRouter({
    mode: "history",
    routes: [
      { path: "/", component: () => fakeComponent("Home") },
      { path: "/features", component: () => fakeComponent("Features") },
    ],
    target,
    scrollBehavior: () => ({ el: "#features" }),
  });
  await router.ready;

  await router.push("/features");

  expect(scrolledIntoView).toBe(true);

  section.remove();
  router.destroy();
});
