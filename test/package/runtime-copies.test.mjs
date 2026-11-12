import assert from "node:assert/strict";
import { execFileSync } from "node:child_process";
import { mkdtempSync, cpSync, writeFileSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join, resolve } from "node:path";
import { pathToFileURL } from "node:url";
const root = resolve(import.meta.dirname, "../..");
execFileSync(process.execPath, ["packages/weiv/scripts/build.mjs"], { cwd: root, stdio: "pipe" });
const temp = mkdtempSync(join(tmpdir(), "weiv-runtime-copies-"));
const tick = () => new Promise(resolve => queueMicrotask(resolve));
try {
  writeFileSync(join(temp, "package.json"), '{"type":"module"}');
  const copies = [];
  for (const name of ["first", "second"]) {
    cpSync(join(root, "packages/weiv/dist/runtime"), join(temp, name), { recursive: true });
    const entry = join(temp, `${name}.mjs`);
    writeFileSync(
      entry,
      `export {observable,subscribe,snapshot,isObservable} from './${name}/observable.js'; export {createCell,createCellScope} from './${name}/cell.js'; export {reactiveScheduler} from './${name}/reactive-core.js';`,
    );
    copies.push(await import(pathToFileURL(entry)));
    const bundled = join(temp, `${name}-bundle.mjs`);
    execFileSync("bun", ["build", entry, "--target", "browser", "--format", "esm", "--outfile", bundled], {
      cwd: root,
      stdio: "pipe",
    });
    copies.push(await import(pathToFileURL(bundled)));
  }
  const first = copies[0];
  const shared = first.observable({ child: { count: 0 } });
  for (const runtime of copies) {
    assert.equal(runtime.reactiveScheduler, first.reactiveScheduler);
    assert.equal(runtime.observable(shared), shared);
    assert.equal(runtime.isObservable(shared), true);
    const snapshot = first.snapshot(shared);
    assert.equal(runtime.createCell(snapshot).value, snapshot);
  }
  const a = copies[1].createCell(shared),
    b = copies[3].createCell({ count: 0 });
  const updates = [];
  const scope = copies[2].createCellScope(dirty => updates.push([...dirty].sort()));
  scope.watch(a, "shared");
  scope.watch(b, "other");
  shared.child.count++;
  b.value.count++;
  await tick();
  assert.deepEqual(updates, [["other", "shared"]]);
  const captured = copies[3].snapshot(shared);
  a.value = captured;
  await tick();
  assert.equal(a.value, captured);
  shared.child.count++;
  await tick();
  assert.equal(updates.length, 2);
  scope.dispose();
  b.value.count++;
  await tick();
  assert.equal(updates.length, 2);

  // The legacy unversioned brand exposes private graph data, but it does not
  // prove that the current implementation can share that graph or scheduler.
  const legacy = { count: 5 };
  legacy.self = legacy;
  Object.defineProperty(legacy, Symbol.for("weiv.observable"), {
    value: {
      target: legacy,
      proxy: legacy,
      listeners: new Set(),
      parents: new Map(),
      root: { pending: new Map(), scheduled: false },
    },
  });
  const target = first.createCell({ count: 0 });
  assert.equal(first.isObservable(legacy), false);
  assert.throws(() => first.observable(legacy), /Incompatible Weiv observable runtime or realm/);
  assert.throws(() => first.subscribe(legacy, () => {}), /Incompatible Weiv observable runtime or realm/);
  assert.throws(() => (target.value = legacy), /Incompatible Weiv observable runtime or realm/);
  assert.equal(target.value.count, 0);
  const adapted = first.snapshot(legacy);
  assert.equal(adapted.count, 5);
  assert.equal(adapted.self, adapted);
  assert(Object.isFrozen(adapted));
  assert.equal(copies[3].createCell(adapted).value, adapted);
  assert.equal(Object.getOwnPropertySymbols(adapted).length, 0);
  console.log(
    "Compatible runtime copies share proxies, snapshots and scheduler; incompatible branded data requires explicit transfer",
  );
} finally {
  rmSync(temp, { recursive: true, force: true });
}
