import { test } from "bun:test";
import { emitLegacyBrowserModule as emitDirectBrowserModule, installJsdom, loadModules } from "./support";

test("custom component prop accepts a template literal", async () => {
  const modules = await loadModules({
    "TemplatePropChild.mjs": emitDirectBrowserModule("test/examples/basic/TemplatePropChild.weiv"),
    "template-prop-parent.mjs": emitDirectBrowserModule("test/examples/basic/template-prop-parent.weiv"),
  });
  const { document } = installJsdom();
  const target = document.createElement("div");
  document.body.append(target);
  const handle = modules["template-prop-parent.mjs"].mount(target, { id: "exposure" });
  if (target.textContent !== "help-exposure") throw new Error(`Unexpected prop: ${target.innerHTML}`);
  handle.setProps({ id: "contrast" });
  handle.update();
  if (target.textContent !== "help-contrast") throw new Error(`Prop did not update: ${target.innerHTML}`);
});
