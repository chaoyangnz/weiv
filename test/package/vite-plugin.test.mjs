import { mkdtempSync, readFileSync, readdirSync, realpathSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join, resolve } from "node:path";
import { build, createLogger } from "vite";
import { weiv } from "../../packages/weiv/src/vite.mjs";

const repoRoot = resolve(import.meta.dirname, "../..");
const tempRoot = realpathSync(mkdtempSync(join(tmpdir(), "weiv-vite-plugin-")));
const distRoot = join(tempRoot, "dist");
const previousBinary = process.env.WEIV_BINARY_PATH;
const warnings = [];
const logger = createLogger("info", { prefix: "" });
logger.warn = message => warnings.push(message);

try {
  process.env.WEIV_BINARY_PATH = previousBinary || join(repoRoot, "cyna-out", "bin", "weiv");

  writeFileSync(
    join(tempRoot, "index.html"),
    '<main id="app"></main><script type="module" src="/main.js"></script>',
  );
  writeFileSync(
    join(tempRoot, "main.js"),
    'import * as App from "./App.weiv"; import "./App.weiv?weiv-style.css"; App.mount(document.querySelector("#app"), {});',
  );
  writeFileSync(
    join(tempRoot, "App.weiv"),
    `<template><h1 v-if="title" class="proof">{{ title }}</h1><Child /></template>
<script lang="ts">import * as Child from "./Child.weiv"; let title = "Scoped CSS proof";</script>
<style>.proof { color: rebeccapurple; }</style>
`,
  );
  writeFileSync(
    join(tempRoot, "Child.weiv"),
    '<template><span>Sibling component proof</span></template><script lang="ts">export let props = {};</script>',
  );

  await build({
    root: tempRoot,
    logLevel: "silent",
    customLogger: logger,
    plugins: [weiv()],
    build: { outDir: distRoot, cssMinify: false, minify: false },
  });

  const assetNames = readdirSync(join(distRoot, "assets"));
  const cssName = assetNames.find(name => name.endsWith(".css"));
  const jsName = assetNames.find(name => name.endsWith(".js"));
  if (!cssName) throw new Error("Vite did not emit CSS for the Weiv component");
  if (!jsName) throw new Error("Vite did not emit JavaScript for the Weiv component");

  const css = readFileSync(join(distRoot, "assets", cssName), "utf8");
  const js = readFileSync(join(distRoot, "assets", jsName), "utf8");
  if (!css.includes("rebeccapurple")) {
    throw new Error(`Vite CSS output omitted the component style: ${css}`);
  }
  if (!css.includes("data-weiv-scope")) {
    throw new Error(`Vite CSS output was not scoped: ${css}`);
  }
  if (!js.includes("data-weiv-scope")) {
    throw new Error("Vite JavaScript output omitted Weiv scope metadata");
  }
  if (!js.includes("Sibling component proof")) {
    throw new Error("Vite did not bundle the sibling Weiv component");
  }
  if (
    !warnings.some(
      warning => warning.includes("directive.vue_structural_syntax") && warning.includes("use #if"),
    )
  ) {
    throw new Error(`Vite did not report the Vue structural syntax warning: ${warnings.join("\n")}`);
  }

  console.log("Vite plugin emitted scoped Weiv CSS and migration diagnostics");
} finally {
  if (previousBinary === undefined) delete process.env.WEIV_BINARY_PATH;
  else process.env.WEIV_BINARY_PATH = previousBinary;
  rmSync(tempRoot, { recursive: true, force: true });
}
