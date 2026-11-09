import assert from "node:assert/strict";
import { execFileSync } from "node:child_process";
import { mkdtempSync, writeFileSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join, resolve } from "node:path";

const root = resolve(import.meta.dirname, "../..");
const binary = process.env.WEIV_BINARY_PATH || join(root, "cyna-out/bin/weiv");
const dir = mkdtempSync(join(tmpdir(), "weiv-module-state-"));
function analyze(source) {
  const path = join(dir, "state.ts");
  writeFileSync(path, source);
  return JSON.parse(execFileSync(binary, ["analyze", "module-state", path], { cwd: root, encoding: "utf8" }));
}
try {
  const report = analyze(`
    import { observable as track } from "weiv:observable";
    import type { Model } from "./types";
    import { library } from "outside";
    export const state = track({ count: 0 });
    export const raw = { count: 0 };
    export const title = "fixed";
    export function read() { return library.count; }
    export function format(library) { return library.count; }
    export function invoke(value) { return value.next(); }
    export { state as alias };
    export { store as reexported } from "./other";
    export * as namespace from "./namespace";
    export type { Model };
  `);
  assert.equal(report.ok, true);
  assert.equal(report.managed, false);
  assert.deepEqual(report.diagnostics, []);
  assert.equal(report.bindings.find(b => b.name === "state").value_kind, "observable");
  assert.equal(report.bindings.find(b => b.name === "raw").value_kind, "object");
  assert.equal(report.bindings.find(b => b.name === "title").value_kind, "primitive");
  assert.deepEqual(report.bindings.find(b => b.name === "read").reads, ["library"]);
  assert.deepEqual(report.bindings.find(b => b.name === "format").reads, []);
  assert.deepEqual(report.bindings.find(b => b.name === "invoke").calls, ["value.next"]);
  assert.equal(report.exports.find(e => e.exported === "alias").local, "state");
  assert.equal(report.exports.find(e => e.exported === "reexported").source, "./other");
  assert.equal(report.exports.find(e => e.exported === "namespace").kind, "namespace_reexport");
  assert(!report.imports.some(i => i.local === "Model"));
  assert(!report.exports.some(e => e.exported === "Model"));
  const mutable = analyze("export let state = 0; export function replace(){ state = 1; }");
  assert.deepEqual(mutable.root_writes, ["state"]);
  const invalid = analyze("export const state = ;");
  assert.equal(invalid.ok, false);
  assert(invalid.diagnostics.length > 0);
  console.log("Module state facts preserve lexical origins, reexports and explicit unmanaged coverage");
} finally {
  rmSync(dir, { recursive: true, force: true });
}
