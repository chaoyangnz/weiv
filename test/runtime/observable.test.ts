import { expect, test } from "bun:test";
import {
  isObservable,
  observable,
  observableBrandSymbol,
  snapshot,
  subscribe,
} from "../../packages/weiv/src/runtime/observable";

test("observable batches multiple sync writes into one notification", async () => {
  const state = observable({ count: 0, label: "draft" });
  let calls = 0;

  const unsubscribe = subscribe(state, () => {
    calls += 1;
  });

  state.count += 1;
  state.label = "ready";

  expect(calls).toBe(0);
  await new Promise(resolve => queueMicrotask(resolve));
  expect(calls).toBe(1);

  unsubscribe();
});

test("observable notifies nested and root subscribers for nested mutation", async () => {
  const state = observable({
    detail: {
      status: "open",
    },
  });

  let rootCalls = 0;
  let nestedCalls = 0;

  subscribe(state, () => {
    rootCalls += 1;
  });
  subscribe(state.detail, () => {
    nestedCalls += 1;
  });

  state.detail.status = "done";

  await new Promise(resolve => queueMicrotask(resolve));
  expect(rootCalls).toBe(1);
  expect(nestedCalls).toBe(1);
});

test("observable reports batched property paths to root and nested subscribers", async () => {
  const state = observable({ detail: { status: "open", label: "draft" }, other: 0 });
  let rootPaths: ReadonlySet<string> | null = null;
  let nestedPaths: ReadonlySet<string> | null = null;
  subscribe(state, paths => {
    rootPaths = paths;
  });
  subscribe(state.detail, paths => {
    nestedPaths = paths;
  });

  state.detail.status = "done";
  state.other = 1;
  await new Promise(resolve => queueMicrotask(resolve));

  expect([...rootPaths!].sort()).toEqual(["detail.status", "other"]);
  expect([...nestedPaths!]).toEqual(["status"]);
});

test("snapshot returns a frozen plain view of current state", () => {
  const state = observable({
    count: 2,
    detail: {
      label: "release",
    },
  });

  const snap = snapshot(state);

  expect(snap).not.toBe(state);
  expect(Object.isFrozen(snap)).toBe(true);
  expect(Object.isFrozen(snap.detail)).toBe(true);
  expect(snap.count).toBe(2);
  expect(snap.detail.label).toBe("release");
});

test("array mutations notify subscribers", async () => {
  const state = observable({
    items: ["a"],
  });

  let calls = 0;
  subscribe(state.items, () => {
    calls += 1;
  });

  state.items.push("b");

  await new Promise(resolve => queueMicrotask(resolve));
  expect(calls).toBe(1);
});

test("array index writes report length as a dependent path", async () => {
  const state = observable({ items: ["a"] });
  let paths: ReadonlySet<string> | null = null;
  subscribe(state, changed => {
    paths = changed;
  });

  state.items.push("b");
  await new Promise(resolve => queueMicrotask(resolve));

  expect(paths?.has("items.length")).toBe(true);
});

test("observable preserves nested proxy identity across repeated reads", () => {
  const state = observable({
    detail: {
      label: "release",
    },
  });

  expect(state.detail).toBe(state.detail);
  expect(isObservable(state)).toBe(true);
  expect(isObservable(state.detail)).toBe(true);
});

test("observable wraps replacement objects on next read", async () => {
  const state = observable({
    detail: {
      label: "release",
    },
  });

  let calls = 0;
  subscribe(state, () => {
    calls += 1;
  });

  state.detail = { label: "rollback" };

  await new Promise(resolve => queueMicrotask(resolve));
  expect(calls).toBe(1);
  expect(isObservable(state.detail)).toBe(true);
  expect(state.detail.label).toBe("rollback");
});

test("unsubscribe stops future notifications", async () => {
  const state = observable({ count: 0 });
  let calls = 0;

  const unsubscribe = subscribe(state, () => {
    calls += 1;
  });

  state.count = 1;
  await new Promise(resolve => queueMicrotask(resolve));
  expect(calls).toBe(1);

  unsubscribe();

  state.count = 2;
  await new Promise(resolve => queueMicrotask(resolve));
  expect(calls).toBe(1);
});

test("observable called on an existing proxy returns the same proxy", () => {
  const state = observable({ count: 0 });
  expect(observable(state)).toBe(state);
});

test("replaced nested object no longer notifies its old parent chain", async () => {
  const state = observable({
    detail: {
      label: "release",
    },
  });

  const oldDetail = state.detail;
  let rootCalls = 0;
  let oldDetailCalls = 0;

  subscribe(state, () => {
    rootCalls += 1;
  });
  subscribe(oldDetail, () => {
    oldDetailCalls += 1;
  });

  state.detail = { label: "rollback" };
  await new Promise(resolve => queueMicrotask(resolve));
  expect(rootCalls).toBe(1);

  oldDetail.label = "stale local edit";
  await new Promise(resolve => queueMicrotask(resolve));

  expect(rootCalls).toBe(1);
  expect(oldDetailCalls).toBe(1);
  expect(state.detail.label).toBe("rollback");
});

test("delete notifies parent and detaches removed nested object", async () => {
  const state = observable({
    detail: {
      label: "release",
    },
  }) as { detail?: { label: string } };

  const oldDetail = state.detail!;
  let rootCalls = 0;

  subscribe(state, () => {
    rootCalls += 1;
  });

  delete state.detail;
  await new Promise(resolve => queueMicrotask(resolve));
  expect(rootCalls).toBe(1);
  expect("detail" in state).toBe(false);

  oldDetail.label = "detached";
  await new Promise(resolve => queueMicrotask(resolve));
  expect(rootCalls).toBe(1);
});

test("snapshot reflects nested replacement and remains detached from later writes", () => {
  const state = observable({
    detail: {
      label: "release",
    },
  });

  state.detail = { label: "rollback" };
  const snap = snapshot(state);

  expect(snap.detail.label).toBe("rollback");

  state.detail.label = "final";
  expect(snap.detail.label).toBe("rollback");
});

test("array splice notifies root and nested array subscribers once", async () => {
  const state = observable({
    items: [
      { id: "a", done: false },
      { id: "b", done: false },
      { id: "c", done: true },
    ],
  });

  let rootCalls = 0;
  let arrayCalls = 0;

  subscribe(state, () => {
    rootCalls += 1;
  });
  subscribe(state.items, () => {
    arrayCalls += 1;
  });

  state.items.splice(1, 1, { id: "b2", done: true });

  await new Promise(resolve => queueMicrotask(resolve));
  expect(rootCalls).toBe(1);
  expect(arrayCalls).toBe(1);
  expect(state.items[1].id).toBe("b2");
  expect(isObservable(state.items[1])).toBe(true);
});

test("array pop detaches removed object from parent chain", async () => {
  const state = observable({
    items: [
      { id: "a", done: false },
      { id: "b", done: false },
    ],
  });

  let rootCalls = 0;
  subscribe(state, () => {
    rootCalls += 1;
  });

  const removed = state.items[1];
  state.items.pop();

  await new Promise(resolve => queueMicrotask(resolve));
  expect(rootCalls).toBe(1);

  removed.done = true;
  await new Promise(resolve => queueMicrotask(resolve));
  expect(rootCalls).toBe(1);
});

test("array sort keeps notifying through the same array proxy", async () => {
  const state = observable({
    items: [3, 1, 2],
  });

  const arrayRef = state.items;
  let calls = 0;
  subscribe(arrayRef, () => {
    calls += 1;
  });

  state.items.sort((a, b) => a - b);

  await new Promise(resolve => queueMicrotask(resolve));
  expect(calls).toBe(1);
  expect(state.items).toBe(arrayRef);
  expect(state.items.join(",")).toBe("1,2,3");
});

test("multiple subscriptions on the same observable all receive the same flush", async () => {
  const state = observable({ count: 0 });

  let callsA = 0;
  let callsB = 0;

  subscribe(state, () => {
    callsA += 1;
  });
  subscribe(state, () => {
    callsB += 1;
  });

  state.count = 1;

  await new Promise(resolve => queueMicrotask(resolve));
  expect(callsA).toBe(1);
  expect(callsB).toBe(1);
});

test("assigning an already observable nested object preserves its proxy identity", async () => {
  const other = observable({
    detail: {
      label: "shared",
    },
  });

  const state = observable({
    detail: {
      label: "local",
    },
  });

  state.detail = other.detail;

  await new Promise(resolve => queueMicrotask(resolve));
  expect(state.detail).toBe(other.detail);
  expect(state.detail.label).toBe("shared");
});

test("subscribing to a non-observable throws clearly", () => {
  expect(() => subscribe({ plain: true }, () => {})).toThrow(
    "subscribe() expects a value created by observable()",
  );
});

test("observable exposes a non-enumerable Weiv brand symbol", () => {
  const state = observable({ count: 0 });
  const brand = observableBrandSymbol();

  expect(isObservable(state)).toBe(true);
  expect(Reflect.get(state, brand)).toBeDefined();
  expect(Object.keys(state)).not.toContain(String(brand));
  expect(Object.getOwnPropertySymbols(state)).toContain(brand);
});

test("observable called with an already observable nested proxy returns that same proxy", () => {
  const state = observable({
    detail: {
      count: 1,
    },
  });

  expect(observable(state.detail)).toBe(state.detail);
});
