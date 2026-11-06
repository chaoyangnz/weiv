import { test } from "bun:test";
import {
  emitLegacyBrowserModule as emitDirectBrowserModule,
  installJsdom,
  loadModules,
} from "./support";

function clickButton(target: Element, win: any) {
  const button = target.querySelector("button");
  if (!button) throw new Error("Missing button");
  button.dispatchEvent(new win.Event("click", { bubbles: true }));
}

test("basic counter works with jsdom real DOM", async () => {
  const modules = await loadModules({
    "BasicCounter.mjs": emitDirectBrowserModule("test/examples/basic/basic-counter.weiv"),
  });

  const mod = modules["BasicCounter.mjs"];
  const { document: doc, window: win } = installJsdom();
  const target = doc.createElement("div");
  doc.body.appendChild(target);

  mod.mount(target, { title: "Counter", initialCount: 2 });

  if (!target.textContent?.includes("Current count: 2")) {
    throw new Error(`Initial text mismatch: ${target.textContent}`);
  }
  if (!target.textContent?.includes("Doubled: 4")) {
    throw new Error(`Initial doubled mismatch: ${target.textContent}`);
  }

  clickButton(target, win);

  if (!target.textContent?.includes("Current count: 3")) {
    throw new Error(`After click text mismatch: ${target.textContent}`);
  }
  if (!target.textContent?.includes("Doubled: 6")) {
    throw new Error(`After click doubled mismatch: ${target.textContent}`);
  }

  for (let i = 0; i < 7; i++) clickButton(target, win);

  const button = target.querySelector("button") as any;
  if (!button?.disabled) {
    throw new Error("Button should be disabled after reaching limit");
  }
});

test("external callbacks update through the explicit Weiv boundary", async () => {
  const modules = await loadModules({
    "ExternalCallback.mjs": emitDirectBrowserModule("test/examples/basic/external-callback.weiv"),
  });
  const { document: doc, window: win } = installJsdom();
  (globalThis as any).window = win;
  const target = doc.createElement("div");
  doc.body.appendChild(target);

  modules["ExternalCallback.mjs"].mount(target, {});
  const count = target.querySelector(".count");
  if (count?.textContent?.trim() !== "0") throw new Error("External callback fixture did not render initial state");

  win.dispatchEvent(new win.Event("weiv-unowned"));
  if (count.textContent?.trim() !== "0") throw new Error("Unowned callback unexpectedly flushed local state");

  win.dispatchEvent(new win.Event("weiv-owned"));
  if (count.textContent?.trim() !== "2") throw new Error(`Explicit update boundary did not flush local state: ${count.textContent}`);
});

test("conditional toggle works with jsdom real DOM", async () => {
  const modules = await loadModules({
    "ConditionalToggle.mjs": emitDirectBrowserModule("test/examples/basic/conditional-toggle.weiv"),
  });

  const mod = modules["ConditionalToggle.mjs"];
  const { document: doc, window: win } = installJsdom();
  const target = doc.createElement("div");
  doc.body.appendChild(target);

  mod.mount(target, {});

  if (!target.textContent?.includes("Panel is closed")) {
    throw new Error(`Initial branch mismatch: ${target.textContent}`);
  }

  clickButton(target, win);

  if (!target.textContent?.includes("Panel is open")) {
    throw new Error(`After toggle mismatch: ${target.textContent}`);
  }
  if (target.textContent?.includes("Panel is closed")) {
    throw new Error("Old branch still visible after toggle");
  }
});

test("dynamic loops, call handlers, and style bindings work with jsdom real DOM", async () => {
  const modules = await loadModules({
    "NestedConditionalList.mjs": emitDirectBrowserModule("test/examples/basic/nested-conditional-list.weiv"),
  });

  const mod = modules["NestedConditionalList.mjs"];
  const { document: doc, window: win } = installJsdom();
  const target = doc.createElement("div");
  doc.body.appendChild(target);

  mod.mount(target, {});

  let buttons = target.querySelectorAll("button");
  const firstStrategyButton = buttons[2];
  if (!firstStrategyButton) throw new Error("Missing first loop event button");
  firstStrategyButton.dispatchEvent(new win.Event("click", { bubbles: true }));

  if (!target.textContent?.includes("Firstselected")) {
    throw new Error(`Argument-bearing loop event did not flush: ${target.textContent}`);
  }

  const firstArticle = target.querySelector("article") as HTMLElement | null;
  if (firstArticle?.style.left !== "58%" || firstArticle.style.width !== "60px") {
    throw new Error(`Dynamic style binding did not populate CSSStyleDeclaration: ${firstArticle?.style.cssText}`);
  }

  const appendButton = buttons[1];
  if (!appendButton) throw new Error("Missing append button");
  appendButton.dispatchEvent(new win.Event("click", { bubbles: true }));

  const articles = target.querySelectorAll("article");
  if (articles.length !== 4) {
    throw new Error(`Reactive loop append expected 4 entries, found ${articles.length}`);
  }
  for (const title of ["First", "Second", "Third", "Fourth"]) {
    if ((target.textContent?.match(new RegExp(title, "g")) ?? []).length !== 1) {
      throw new Error(`Reactive loop append duplicated ${title}: ${target.textContent}`);
    }
  }
});

test("todo list works with jsdom real DOM", async () => {
  const modules = await loadModules({
    "TodoList.mjs": emitDirectBrowserModule("test/examples/basic/todo-list.weiv"),
  });

  const mod = modules["TodoList.mjs"];
  const { document: doc, window: win } = installJsdom();
  const target = doc.createElement("div");
  doc.body.appendChild(target);

  mod.mount(target, { title: "Tasks" });

  if (!target.textContent?.includes("Showing pending tasks")) {
    throw new Error(`Initial filter mismatch: ${target.textContent}`);
  }
  if (!target.textContent?.includes("Implement template binder")) {
    throw new Error(`Missing pending item: ${target.textContent}`);
  }
  if (target.textContent?.includes("Write parser fixtures")) {
    throw new Error("Completed item visible in pending mode");
  }

  clickButton(target, win);

  if (!target.textContent?.includes("Showing completed tasks")) {
    throw new Error(`After toggle filter mismatch: ${target.textContent}`);
  }
  if (!target.textContent?.includes("Write parser fixtures")) {
    throw new Error(`Missing completed item: ${target.textContent}`);
  }
});

test("timer callback works with jsdom real DOM", async () => {
  const modules = await loadModules({
    "TimerCallback.mjs": emitDirectBrowserModule("test/examples/basic/timer-callback.weiv"),
  });

  const mod = modules["TimerCallback.mjs"];
  const { document: doc, window: win } = installJsdom();
  const target = doc.createElement("div");
  doc.body.appendChild(target);

  mod.mount(target, {});

  if (!target.textContent?.includes("0")) {
    throw new Error(`Initial content mismatch: ${target.textContent}`);
  }

  clickButton(target, win);
  await new Promise((resolve) => setTimeout(resolve, 10));

  if (!target.textContent?.includes("1")) {
    throw new Error(`After timer callback mismatch: ${target.textContent}`);
  }
});
