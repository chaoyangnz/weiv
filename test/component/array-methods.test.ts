import { test } from "bun:test";
import { FakeDocument, emitDirectBrowserModule, installDocument, loadModules } from "./support";

test("tracked prop arrays support native map and filter", async () => {
  const modules = await loadModules({
    "ArrayMethods.mjs": emitDirectBrowserModule("test/examples/basic/array-methods.weiv"),
  });
  const document = new FakeDocument();
  const target = document.createElement("div");
  document.body.append(target);
  installDocument(document);
  modules["ArrayMethods.mjs"].mount(target, {
    items: [
      { name: "first", active: true },
      { name: "second", active: false },
    ],
  });
  if (!target.textContent.includes("first-second") || !target.textContent.includes("1")) {
    throw new Error(`Array methods returned unexpected content: ${target.textContent}`);
  }
});
