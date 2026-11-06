import { test } from "bun:test";
import { emitLegacyBrowserModule as emitDirectBrowserModule, installJsdom, loadModules } from "./support";

test("boolean ARIA bindings write true and false strings", async () => {
  const modules = await loadModules({
    "AriaTabs.mjs": emitDirectBrowserModule("test/examples/basic/aria-tabs.weiv"),
  });
  const { document, window } = installJsdom();
  const target = document.createElement("div");
  document.body.append(target);
  modules["AriaTabs.mjs"].mount(target, {});
  const tabs = target.querySelectorAll('[role="tab"]');
  if (tabs[0]?.getAttribute("aria-selected") !== "true" || tabs[1]?.getAttribute("aria-selected") !== "false") {
    throw new Error(`Initial ARIA state is wrong: ${target.innerHTML}`);
  }
  tabs[1].dispatchEvent(new window.Event("click"));
  if (tabs[0].getAttribute("aria-selected") !== "false" || tabs[1].getAttribute("aria-selected") !== "true") {
    throw new Error(`Updated ARIA state is wrong: ${target.innerHTML}`);
  }
});
