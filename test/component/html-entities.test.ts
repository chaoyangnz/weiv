import { test } from "bun:test";
import { emitDirectBrowserModule, installJsdom, loadModules } from "./support";

test("static template text and attributes decode HTML entities", async () => {
  const modules = await loadModules({
    "HtmlEntities.mjs": emitDirectBrowserModule("test/examples/basic/html-entities.weiv"),
  });
  const { document } = installJsdom();
  const target = document.createElement("div");
  document.body.append(target);
  modules["HtmlEntities.mjs"].mount(target, {});
  const paragraph = target.querySelector("p");
  if (paragraph?.textContent !== "WORKSPACE & DATA 🙂 © — &unknown;") {
    throw new Error(`Unexpected decoded text: ${paragraph?.textContent}`);
  }
  if (paragraph.getAttribute("title") !== "WORKSPACE & DATA") {
    throw new Error(`Unexpected decoded attribute: ${paragraph.getAttribute("title")}`);
  }
});
