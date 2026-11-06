import { test } from "bun:test";
import { emitLegacyBrowserModule as emitDirectBrowserModule, installJsdom, loadModules } from "./support";

test("inline SVG uses SVG namespace and preserves viewBox", async () => {
  const modules = await loadModules({
    "SvgNamespace.mjs": emitDirectBrowserModule("test/examples/basic/svg-namespace.weiv"),
  });
  const { document } = installJsdom();
  const target = document.createElement("div");
  document.body.append(target);
  modules["SvgNamespace.mjs"].mount(target, {});
  const svg = target.querySelector("svg");
  const path = target.querySelector("path");
  const circle = target.querySelector("circle");
  const rects = target.querySelectorAll("rect");
  const htmlChild = target.querySelector("foreignObject div");
  if (!svg || !path || !circle || !htmlChild || rects.length !== 2) throw new Error("SVG fixture did not mount all children");
  for (const node of [svg, path, circle, ...rects]) {
    if (node.namespaceURI !== "http://www.w3.org/2000/svg") throw new Error(`${node.localName} has wrong namespace`);
  }
  if (svg.getAttribute("viewBox") !== "0 0 10 10") throw new Error("SVG viewBox was not preserved");
  if (htmlChild.namespaceURI !== "http://www.w3.org/1999/xhtml") throw new Error("foreignObject child has wrong namespace");
});
