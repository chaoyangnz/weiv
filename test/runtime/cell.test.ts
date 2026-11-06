import { expect, test } from "bun:test";
import { createCell, createCellScope, createModuleState, afterModuleWrite, assignmentTarget, cellAssignmentTarget } from "../../packages/weiv/src/runtime/cell";
import { observable, subscribe } from "../../packages/weiv/src/runtime/observable";

const tick = () => new Promise<void>(resolve => queueMicrotask(resolve));

test("assignment adapters defer reads until GetValue and writes until PutValue", () => {
  const trace: string[]=[];
  const cell=createCell(0);
  const target=cellAssignmentTarget(()=>{trace.push('cell');return cell});
  expect(trace).toEqual([]);
  const source={get count(){trace.push('get');return 2}};
  ({count:target.value}=source);
  expect(trace).toEqual(['get','cell']);expect(cell.value).toBe(2);
  trace.length=0;
  target.value+=(trace.push('rhs'),3);
  expect(trace).toEqual(['cell','rhs','cell']);expect(cell.value).toBe(5);
  const writeOnly=assignmentTarget(()=>{throw Error('read')},value=>{trace.push('write-'+value)});
  expect(writeOnly.value=7).toBe(7);
  expect(()=>writeOnly.value++).toThrow('read');
  expect(trace.at(-1)).toBe('write-7');
});

test("module publishers retain subscriptions established before initialization", async () => {
  const module = createModuleState();
  const first = module.getCell("state");
  let updates = 0;
  const scope = createCellScope(() => { updates++; });
  scope.watch(first, "state");
  const shared = observable({ count: 0 });
  module.publish("state", shared);
  expect(first).toBe(module.getCell("state"));
  expect(first.value).toBe(shared);
  await tick();
  expect(updates).toBe(1);
  shared.count++;
  await tick();
  expect(updates).toBe(2);
  scope.dispose();
  shared.count++;
  await tick();
  expect(updates).toBe(2);
});

test("successful module writes publish the current binding and retain expression results", async () => {
  const module = createModuleState();
  let value = 0, lookups = 0;
  module.publish("value", value);
  const getModule = () => { lookups++; return module; };
  expect(afterModuleWrite(getModule, "value", value++, () => value)).toBe(0);
  expect(module.getCell("value").value).toBe(1);
  expect(lookups).toBe(1);
  expect(() => afterModuleWrite(getModule, "value", (() => { throw Error("rhs"); })(), () => value)).toThrow("rhs");
  expect(lookups).toBe(1);
  await tick();
});

test("scalar cells batch with object cells and shared observables in one scope", async () => {
  const count = createCell(0);
  const object = createCell({ label: "first" });
  const shared = observable({ count: 0 });
  const imported = createCell(shared);
  const updates: string[][] = [];
  const scope = createCellScope<string>(dirty => { updates.push([...dirty]); });
  scope.watch(count, "count"); scope.watch(object, "object"); scope.watch(imported, "shared");
  try {
    expect(imported.value).toBe(shared);
    count.value++; count.value++;
    object.value.label = "second";
    shared.count++;
    await tick();
    expect(updates).toHaveLength(1);
    expect(new Set(updates[0])).toEqual(new Set(["count", "object", "shared"]));
    expect(count.value).toBe(2);
  } finally { scope.dispose(); }
});

test("object replacement normalizes new values and detaches old aliases", async () => {
  const cell = createCell({ nested: { count: 0 } });
  const old = cell.value;
  const oldNested = old.nested;
  let updates = 0;
  const scope = createCellScope(() => { updates++; });
  scope.watch(cell, "value");
  try {
    cell.value = { nested: { count: 10 } };
    await tick();
    expect(updates).toBe(1);
    oldNested.count++;
    await tick();
    expect(updates).toBe(1);
    expect(cell.value.nested.count).toBe(10);
    cell.value.nested.count++;
    await tick();
    expect(updates).toBe(2);
    expect(cell.value.nested.count).toBe(11);
  } finally { scope.dispose(); }
});

test("shared object identity and aliases survive independent cell lifetimes", async () => {
  const shared = observable({ count: 0 });
  const a = createCell(shared), b = createCell(shared);
  let updatesA = 0, updatesB = 0, sharedCalls = 0;
  const scopeA = createCellScope(() => { updatesA++; });
  const scopeB = createCellScope(() => { updatesB++; });
  scopeA.watch(a, "a"); scopeB.watch(b, "b");
  const off = subscribe(shared, () => { sharedCalls++; });
  try {
    expect(a.value).toBe(shared);
    expect(b.value).toBe(shared);
    scopeA.dispose();
    shared.count++;
    await tick();
    expect(updatesA).toBe(0);
    expect(updatesB).toBe(1);
    expect(sharedCalls).toBe(1);
  } finally { scopeA.dispose(); scopeB.dispose(); off(); }
});

test("shared changes notify a cell before its first consumer read", async () => {
  const shared = observable({ count: 0 });
  const cell = createCell(shared);
  let calls = 0;
  const scope = createCellScope(() => { calls++; });
  scope.watch(cell, "value");
  try {
    shared.count++;
    await tick();
    expect(calls).toBe(1);
  } finally { scope.dispose(); }
});

test("disposing after notification cancels a queued scope job", async () => {
  const cell = createCell(0);
  let calls = 0;
  const scope = createCellScope(() => { calls++; });
  scope.watch(cell, "value");
  const off = subscribe(cell, () => scope.dispose());
  try {
    cell.value++;
    await tick();
    expect(calls).toBe(0);
    expect(() => scope.watch(cell, "again")).toThrow("disposed");
    cell.value++;
    await tick();
    expect(calls).toBe(0);
  } finally { off(); scope.dispose(); }
});

test("callback origin, await and detached Promise do not change cell notification", async () => {
  const cell = createCell(0);
  const seen: number[] = [];
  const scope = createCellScope(() => { seen.push(cell.value); });
  scope.watch(cell, "count");
  try {
    const callback = () => { cell.value++; };
    callback();
    await tick();
    callback();
    await tick();
    void Promise.resolve().then(callback);
    await tick(); await tick();
    expect(seen).toEqual([1, 2, 3]);
  } finally { scope.dispose(); }
});

test("reentrant scope updates run in a later wave", async () => {
  const cell = createCell(0);
  const seen: number[] = [];
  const scope = createCellScope(() => {
    seen.push(cell.value);
    if (cell.value === 1) cell.value = 2;
  });
  scope.watch(cell, "value");
  try {
    cell.value = 1;
    await tick(); await tick();
    expect(seen).toEqual([1, 2]);
  } finally { scope.dispose(); }
});

test("scalar equality, expression values and primitive replacements follow JavaScript", async () => {
  const cell = createCell<number | null>(NaN);
  let calls = 0;
  const scope = createCellScope(() => { calls++; });
  scope.watch(cell, "value");
  try {
    cell.value = NaN;
    await tick();
    expect(calls).toBe(0);
    cell.value = 0;
    expect(cell.value++).toBe(0);
    expect(++cell.value).toBe(2);
    cell.value = null;
    await tick();
    expect(calls).toBe(1);
    expect(cell.value).toBeNull();
  } finally { scope.dispose(); }
});

test("unsupported values fail before initial wrapping or replacement mutates state", async () => {
  const unsupported = [new Map(), new Set(), new Date(), Object.freeze({ n: 0 }), new (class Model {})()];
  for (const value of unsupported) {
    expect(() => createCell(value)).toThrow("Weiv observable state");
    expect(() => observable({ nested: value })).toThrow("Weiv observable state");
  }
  let getterCalls = 0;
  expect(() => createCell({ get value() { getterCalls++; return 1; } })).toThrow("data properties");
  expect(getterCalls).toBe(0);
  const cell = createCell<any>({ count: 0 });
  const old = cell.value;
  let calls = 0;
  const scope = createCellScope(() => { calls++; });
  scope.watch(cell, "value");
  try {
    expect(() => { cell.value = new Map(); }).toThrow("plain objects");
    expect(cell.value).toBe(old);
    await tick();
    expect(calls).toBe(0);
    old.count++;
    await tick();
    expect(calls).toBe(1);
    expect(() => { old.bad = new Date(); }).toThrow("plain objects");
    expect("bad" in old).toBe(false);
  } finally { scope.dispose(); }
});

test("cell construction supports cyclic records and arrays", async () => {
  const record: any = { items: [] };
  record.self = record;
  const cell = createCell(record);
  let calls = 0;
  const scope = createCellScope(() => { calls++; });
  scope.watch(cell, "value");
  try {
    expect(cell.value.self).toBe(cell.value);
    cell.value.items.push({ count: 1 });
    await tick();
    expect(calls).toBe(1);
    cell.value.items[0].count++;
    await tick();
    expect(calls).toBe(2);
  } finally { scope.dispose(); }
});

test("shared values do not retain disposed component cells", () => {
  const source = `
    import { createCell, createCellScope } from "./packages/weiv/src/runtime/cell.ts";
    import { observable } from "./packages/weiv/src/runtime/observable.ts";
    const shared = observable({ count: 0 });
    function construct() {
      const cell = createCell(shared);
      const scope = createCellScope(() => {});
      scope.watch(cell, "value");
      scope.dispose();
      return new WeakRef(cell);
    }
    const ref = construct();
    await new Promise(resolve => setTimeout(resolve, 0));
    Bun.gc(true);
    if (ref.deref() !== undefined) throw new Error("Shared state retained disposed cell");
    shared.count++;
    await Promise.resolve();
    console.log("released");
  `;
  const result = Bun.spawnSync([process.execPath, "--eval", source], { cwd: process.cwd() });
  expect(new TextDecoder().decode(result.stderr)).toBe("");
  expect(result.exitCode).toBe(0);
  expect(new TextDecoder().decode(result.stdout).trim()).toBe("released");
});

test("explicit snapshots stay immutable and can be replaced in cells", async () => {
  const { snapshot } = await import("../../packages/weiv/src/runtime/observable");
  const source = observable({ nested: { count: 1 } });
  const captured = snapshot(source);
  const cell = createCell(captured);
  let calls = 0;
  const scope = createCellScope(() => { calls++; });
  scope.watch(cell, "value");
  try {
    expect(cell.value).toBe(captured);
    expect(cell.value.nested).toBe(captured.nested);
    expect(Object.isFrozen(cell.value.nested)).toBe(true);
    source.nested.count = 2;
    await tick();
    expect(cell.value.nested.count).toBe(1);
    expect(calls).toBe(0);
    cell.value = snapshot(source);
    await tick();
    expect(cell.value.nested.count).toBe(2);
    expect(calls).toBe(1);
    expect(() => observable(captured)).toThrow("snapshot");
  } finally { scope.dispose(); }
});
