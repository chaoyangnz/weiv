import { test } from "bun:test";
import { emitLegacyBrowserModule as emitDirectBrowserModule, installJsdom, loadModules } from "./support";

test("compound expressions resolve loop items and component bindings", async () => {
  const modules = await loadModules({
    "CompoundScope.mjs": emitDirectBrowserModule("test/examples/basic/compound-scope.weiv"),
  });
  const { document } = installJsdom();
  const target = document.createElement("div");
  document.body.append(target);
  modules["CompoundScope.mjs"].mount(target, {
    view: { locked: "" }, actions: { text: (id: string) => `label:${id}` },
  });
  if (!target.textContent?.includes("label:first")) throw new Error(`Compound scope failed: ${target.innerHTML}`);
});
