import { test } from "bun:test";
import { emitLegacyBrowserModule as emitDirectBrowserModule, installJsdom, loadModules } from "./support";

test("nested conditional child mounts before receiving prop updates", async () => {
  const modules = await loadModules({
    "NestedConditionalChild.mjs": emitDirectBrowserModule("test/examples/basic/NestedConditionalChild.weiv"),
    "nested-conditional-parent.mjs": emitDirectBrowserModule("test/examples/basic/nested-conditional-parent.weiv"),
  });
  const { document, window } = installJsdom();
  const target = document.createElement("div");
  document.body.append(target);
  modules["nested-conditional-parent.mjs"].mount(target, {});
  if (target.querySelector("output")) throw new Error("Child mounted while tab was closed");
  target.querySelectorAll("button")[0]?.dispatchEvent(new window.Event("click"));
  if (target.querySelector("output")) throw new Error("Child mounted while tab was closed after prop change");
  target.querySelectorAll("button")[1]?.dispatchEvent(new window.Event("click"));
  if (target.querySelector("output")?.textContent !== "10") throw new Error(`Child did not receive its prop: ${target.innerHTML}`);
  target.querySelectorAll("button")[2]?.dispatchEvent(new window.Event("click"));
  target.querySelectorAll("button")[0]?.dispatchEvent(new window.Event("click"));
  if (target.querySelector("output")) throw new Error("Child survived the closed tab");
  target.querySelectorAll("button")[1]?.dispatchEvent(new window.Event("click"));
  if (target.querySelector("output")?.textContent !== "10") throw new Error(`Child did not remount: ${target.innerHTML}`);
});
