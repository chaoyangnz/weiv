import { test } from "bun:test";
import { emitDirectBrowserModule, installJsdom, loadModules } from "./support";

test("HTML void tags mount without explicit self closing syntax", async () => {
  const modules = await loadModules({
    "HtmlVoidTags.mjs": emitDirectBrowserModule("test/examples/basic/html-void-tags.weiv"),
  });
  const { document } = installJsdom();
  const target = document.createElement("div");
  document.body.append(target);
  modules["HtmlVoidTags.mjs"].mount(target, {});
  if (target.querySelector("label > input")?.getAttribute("name") !== "name")
    throw new Error("Nested input did not mount");
  if (!target.querySelector("br") || target.querySelector("img")?.getAttribute("alt") !== "preview") {
    throw new Error("Sibling void tags did not mount");
  }
});
