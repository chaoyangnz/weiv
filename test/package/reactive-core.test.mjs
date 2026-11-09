import assert from "node:assert/strict";
import { execFileSync } from "node:child_process";
import { mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join, resolve } from "node:path";
import { pathToFileURL } from "node:url";
import { build } from "vite";
import { JSDOM } from "jsdom";

const repoRoot = resolve(import.meta.dirname, "../..");
execFileSync(process.execPath, ["packages/weiv/scripts/build.mjs"], { cwd: repoRoot, stdio: "pipe" });
const { weiv } = await import("../../packages/weiv/dist/vite.mjs");
const temp = mkdtempSync(join(tmpdir(), "weiv-core-package-"));
try {
  const entry = join(temp, "entry.js");
  const binary = process.env.WEIV_BINARY_PATH || join(repoRoot, "cyna-out/bin/weiv");
  const compiled = execFileSync(binary, ["emit", "js", "test/examples/basic/compiler-cells.weiv"], { cwd: repoRoot, encoding: "utf8" });
  writeFileSync(join(temp, "Compiled.mjs"), compiled);
  writeFileSync(entry, `
    export { mount as mountCells } from "./Compiled.mjs";
    import { observable, subscribe, snapshot } from "weiv:observable";
    import { createCell, createCellScope } from "weiv:cells";
    export async function checkSnapshotCell() {
      const source = observable({ nested: { count: 0 } });
      const captured = createCell(snapshot(source));
      source.nested.count = 1;
      await new Promise(resolve => queueMicrotask(resolve));
      const retained = captured.value.nested.count;
      captured.value = snapshot(source);
      return { retained, recaptured: captured.value.nested.count };
    }
    export async function checkCells() {
      const shared = observable({ count: 0 });
      const object = createCell(shared), scalar = createCell(0);
      const updates = [];
      const scope = createCellScope(dirty => updates.push([...dirty].sort()));
      scope.watch(object, "object"); scope.watch(scalar, "scalar");
      shared.count++; scalar.value++;
      await new Promise(resolve => queueMicrotask(resolve));
      scope.dispose();
      return { same: object.value === shared, updates };
    }
    export async function check() {
      const a = observable({ count: 0 }), b = observable({ count: 0 });
      const values = [];
      const offA = subscribe(a, () => values.push(a.count));
      const offB = subscribe(b, () => values.push(b.count));
      a.count = 1; b.count = 2;
      await new Promise(resolve => queueMicrotask(resolve));
      offA(); offB();
      return values;
    }
  `);
  await build({
    configFile: false, root: temp, logLevel: "silent", plugins: [weiv()],
    build: {
      outDir: join(temp, "vite"), minify: false,
      lib: { entry, formats: ["es"], fileName: () => "core.mjs" },
    },
  });
  const viteOutput = await import(pathToFileURL(join(temp, "vite/core.mjs")).href);
  assert.deepEqual(await viteOutput.check(), [1, 2]);
  assert.deepEqual(await viteOutput.checkCells(), { same: true, updates: [["object", "scalar"]] });
  assert.deepEqual(await viteOutput.checkSnapshotCell(), { retained: 0, recaptured: 1 });
  await checkCompiled(viteOutput);

  const bunOutput = join(temp, "bun-core.mjs");
  const bunPlugin = pathToFileURL(join(repoRoot, "packages/weiv/dist/bun.mjs")).href;
  const runner = join(temp, "build.mjs");
  writeFileSync(runner, `
    import { weiv } from ${JSON.stringify(bunPlugin)};
    const result = await Bun.build({ entrypoints: [${JSON.stringify(entry)}],
      outdir: ${JSON.stringify(temp)}, naming: "bun-core.mjs", plugins: [weiv()], target: "browser" });
    if (!result.success) throw new AggregateError(result.logs, "Bun runtime bundle failed");
  `);
  execFileSync("bun", [runner], { cwd: repoRoot, stdio: "pipe" });
  const bunModule = await import(pathToFileURL(bunOutput).href);
  assert.deepEqual(await bunModule.check(), [1, 2]);
  assert.deepEqual(await bunModule.checkCells(), { same: true, updates: [["object", "scalar"]] });
  assert.deepEqual(await bunModule.checkSnapshotCell(), { retained: 0, recaptured: 1 });
  await checkCompiled(bunModule);
  console.log("Packaged observable/core imports and notifications pass through Vite and Bun");
} finally {
  rmSync(temp, { recursive: true, force: true });
}

async function checkCompiled(module) {
  const previousWindow = globalThis.window, previousDocument = globalThis.document;
  const dom = new JSDOM("<main></main>");
  globalThis.window = dom.window;
  globalThis.document = dom.window.document;
  let handle;
  try {
    const target = document.querySelector("main");
    handle = module.mountCells(target, { initial: 0 });
    window.dispatchEvent(new window.Event("cells-write"));
    await new Promise(resolve => queueMicrotask(resolve));
    assert.equal(target.querySelector(".count").textContent, "1");
    assert.equal(target.querySelector(".object").textContent, "1");
    const detail = {};
    window.dispatchEvent(new window.CustomEvent("cells-expression", { detail }));
    await new Promise(resolve => queueMicrotask(resolve));
    assert.equal(detail.receiver, true);
    assert.equal(detail.parenthesizedReceiver, true);
    assert.equal(detail.sequenceReceiver, true);
    assert.equal(detail.argumentCalls, 1);
    assert.equal(detail.nonCallable, true);
    const assigned = {};
    window.dispatchEvent(new window.CustomEvent("cells-return", { detail: assigned }));
    await new Promise(resolve => queueMicrotask(resolve));
    assert.equal(assigned.same, true);
    assert.equal(assigned.optionalSame, true);
    assert.equal(target.querySelector(".object").textContent, "21");
  } finally {
    handle?.destroy();
    dom.window.close();
    globalThis.window = previousWindow;
    globalThis.document = previousDocument;
  }
}
