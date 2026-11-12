import { expect, test } from "bun:test";
import { emitDirectBrowserModule, installJsdom, loadModules } from "./support";

test("nested template callback bodies preserve locals and captured state", async () => {
  const modules = await loadModules({
    "TemplateCallbackScope.mjs": emitDirectBrowserModule("test/examples/basic/template-callback-scope.weiv"),
  });
  const { document, window } = installJsdom();
  const target = document.createElement("div");
  const handle = modules["TemplateCallbackScope.mjs"].mount(target, {});
  try {
    expect(target.querySelector("p")?.textContent).toBe('[{"local":4,"next":4}]');
    expect(target.querySelector(".spread")?.textContent).toBe("1");
    expect(target.querySelector(".default")?.textContent).toBe("4");
    target.querySelector("button")!.dispatchEvent(new window.Event("click"));
    await new Promise<void>(resolve => queueMicrotask(resolve));
    await new Promise<void>(resolve => queueMicrotask(resolve));
    expect(target.querySelector("p")?.textContent).toBe('[{"local":4,"next":5}]');
    expect(target.querySelector(".spread")?.textContent).toBe("2");
    expect(target.querySelector(".default")?.textContent).toBe("5");
  } finally {
    handle.destroy();
    window.close();
  }
});

test("template Math and String globals render and update", async () => {
  const modules = await loadModules({
    "TemplateGlobals.mjs": emitDirectBrowserModule("test/examples/basic/template-globals.weiv"),
  });
  const { document, window } = installJsdom();
  const target = document.createElement("div");
  document.body.append(target);
  modules["TemplateGlobals.mjs"].mount(target, {});
  const inputs = target.querySelectorAll("input");
  if (
    !target.textContent?.includes("100%") ||
    inputs.length !== 2 ||
    inputs[0].value !== "7" ||
    inputs[1].value !== "8"
  ) {
    throw new Error(`Template globals did not render correctly: ${target.innerHTML}`);
  }
  target.querySelector("button")?.dispatchEvent(new window.Event("click"));
  await new Promise<void>(resolve => queueMicrotask(resolve));
  if (!target.textContent?.includes("125%")) throw new Error("Math global did not update after click");
});

test("component bindings can shadow template globals", async () => {
  const modules = await loadModules({
    "TemplateGlobalShadow.mjs": emitDirectBrowserModule("test/examples/basic/template-global-shadow.weiv"),
  });
  const { document } = installJsdom();
  const target = document.createElement("div");
  document.body.append(target);
  modules["TemplateGlobalShadow.mjs"].mount(target, {});
  if (target.textContent !== "42")
    throw new Error(`Component Math binding was ignored: ${target.textContent}`);
});
