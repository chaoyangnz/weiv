import { expect, test } from "bun:test";
import { createReactiveScheduler, reactiveScheduler } from "../../packages/weiv/src/runtime/reactive-core";
import { observable, subscribe } from "../../packages/weiv/src/runtime/observable";

function harness(maxWaves = 100) {
  const tasks: Array<() => void> = [];
  const errors: unknown[][] = [];
  const scheduler = createReactiveScheduler({
    enqueue: task => {
      tasks.push(task);
    },
    reportErrors: failures => {
      errors.push(failures);
    },
    maxWaves,
  });
  return { scheduler, tasks, errors, next: () => tasks.shift()!() };
}

test("all roots prepare before delivery, then one job runs per owner", () => {
  const h = harness();
  const events: string[] = [];
  const owner = {};
  for (const name of ["a", "b"]) {
    h.scheduler.notify({}, () => {
      events.push(`prepare ${name}`);
      return () => {
        events.push(`deliver ${name}`);
        h.scheduler.queueJob(owner, () => {
          events.push("render");
        });
      };
    });
  }
  expect(h.tasks).toHaveLength(1);
  h.next();
  expect(events).toEqual(["prepare a", "prepare b", "deliver a", "deliver b", "render"]);
  expect(h.tasks).toHaveLength(0);
});

test("prepare, delivery and job failures do not starve independent work", () => {
  const h = harness();
  const errors = [new Error("prepare"), new Error("deliver"), new Error("job")];
  const events: string[] = [];
  h.scheduler.notify({}, () => {
    throw errors[0];
  });
  h.scheduler.notify({}, () => () => {
    throw errors[1];
  });
  h.scheduler.notify({}, () => () => {
    events.push("notified");
  });
  h.scheduler.queueJob({}, () => {
    throw errors[2];
  });
  h.scheduler.queueJob({}, () => {
    events.push("rendered");
  });
  h.next();
  expect(events).toEqual(["notified", "rendered"]);
  expect(h.errors).toEqual([errors]);
  h.scheduler.queueJob({}, () => {
    events.push("recovered");
  });
  h.next();
  expect(events.at(-1)).toBe("recovered");
});

test("cancelled jobs skip captured delivery, rescheduled jobs wait for next wave", () => {
  const h = harness();
  const owner = {};
  let calls = 0;
  const job = () => {
    calls++;
  };
  h.scheduler.queueJob({}, () => {
    h.scheduler.cancelJob(owner);
    h.scheduler.queueJob(owner, job);
  });
  h.scheduler.queueJob(owner, job);
  h.next();
  expect(calls).toBe(0);
  h.next();
  expect(calls).toBe(1);
  h.scheduler.queueJob(owner, job);
  h.scheduler.cancelJob(owner);
  h.next();
  expect(calls).toBe(1);
});

test("reentrant notifications run in a subsequent microtask wave", () => {
  const h = harness();
  const events: number[] = [];
  h.scheduler.notify({}, () => () => {
    events.push(1);
    h.scheduler.notify({}, () => () => {
      events.push(2);
    });
  });
  h.next();
  expect(events).toEqual([1]);
  expect(h.tasks).toHaveLength(1);
  h.next();
  expect(events).toEqual([1, 2]);
});

test("nonconverging updates are bounded and scheduler remains usable", () => {
  const h = harness(2);
  const owner = {};
  let calls = 0;
  const repeat = () => {
    calls++;
    h.scheduler.queueJob(owner, repeat);
  };
  h.scheduler.queueJob(owner, repeat);
  h.next();
  h.next();
  h.next();
  expect(calls).toBe(2);
  expect(h.tasks).toHaveLength(0);
  expect(String(h.errors[0][0])).toContain("exceeded 2 consecutive waves");
  h.scheduler.queueJob(owner, () => {
    calls++;
  });
  h.next();
  expect(calls).toBe(3);
});

test("observable roots share the scheduler and deduplicate a component job", async () => {
  const a = observable({ count: 0 });
  const b = observable({ count: 0 });
  const owner = {};
  const renders: number[] = [];
  const render = () => {
    renders.push(a.count + b.count);
  };
  const offA = subscribe(a, () => reactiveScheduler.queueJob(owner, render));
  const offB = subscribe(b, () => reactiveScheduler.queueJob(owner, render));
  try {
    a.count++;
    b.count++;
    await new Promise<void>(resolve => queueMicrotask(resolve));
    expect(renders).toEqual([2]);
  } finally {
    offA();
    offB();
    reactiveScheduler.cancelJob(owner);
  }
});

test("observable snapshots all root notifications before reentrant writes", async () => {
  const a = observable({ count: 0 });
  const b = observable({ first: 0, later: 0 });
  const paths: string[][] = [];
  const offA = subscribe(a, () => {
    b.later++;
  });
  const offB = subscribe(b, changed => {
    paths.push([...changed!]);
  });
  try {
    a.count++;
    b.first++;
    await new Promise<void>(resolve => queueMicrotask(resolve));
    await new Promise<void>(resolve => queueMicrotask(resolve));
    expect(paths).toEqual([["first"], ["later"]]);
  } finally {
    offA();
    offB();
  }
});

test("new listeners wait for a future change and disposed listeners are skipped", async () => {
  const a = observable({ count: 0 });
  const b = observable({ count: 0 });
  let lateCalls = 0;
  let disposedCalls = 0;
  let offLate = () => {};
  const offA = subscribe(a, () => {
    offB();
    offLate = subscribe(b, () => {
      lateCalls++;
    });
  });
  const offB = subscribe(b, () => {
    disposedCalls++;
  });
  try {
    a.count++;
    b.count++;
    await new Promise<void>(resolve => queueMicrotask(resolve));
    expect(lateCalls).toBe(0);
    expect(disposedCalls).toBe(0);
    b.count++;
    await new Promise<void>(resolve => queueMicrotask(resolve));
    expect(lateCalls).toBe(1);
  } finally {
    offA();
    offB();
    offLate();
  }
});

test("default reporter exposes subscriber errors after all subscribers run", () => {
  const source = `
    import { observable, subscribe } from "./packages/weiv/src/runtime/observable.ts";
    const state = observable({ count: 0 });
    const events = [];
    subscribe(state, () => { events.push("first"); throw new Error("failed"); });
    subscribe(state, () => { events.push("second"); });
    process.on("uncaughtException", error => {
      console.log(JSON.stringify({events, aggregate: error instanceof AggregateError,
        cause: error.errors[0].errors[0].message}));
    });
    state.count++;
  `;
  const result = Bun.spawnSync([process.execPath, "--eval", source], { cwd: process.cwd() });
  expect(result.exitCode).toBe(0);
  expect(JSON.parse(new TextDecoder().decode(result.stdout))).toEqual({
    events: ["first", "second"],
    aggregate: true,
    cause: "failed",
  });
});

test("resubscribing the same callback does not revive a disposed captured registration", async () => {
  const a = observable({ count: 0 });
  const b = observable({ count: 0 });
  let calls = 0;
  const listener = () => {
    calls++;
  };
  let offB = subscribe(b, listener);
  const offA = subscribe(a, () => {
    offB();
    offB = subscribe(b, listener);
  });
  try {
    a.count++;
    b.count++;
    await new Promise<void>(resolve => queueMicrotask(resolve));
    expect(calls).toBe(0);
    b.count++;
    await new Promise<void>(resolve => queueMicrotask(resolve));
    expect(calls).toBe(1);
  } finally {
    offA();
    offB();
  }
});

test("subscriptions using the same callback dispose independently", async () => {
  const state = observable({ count: 0 });
  let calls = 0;
  const listener = () => {
    calls++;
  };
  const offA = subscribe(state, listener);
  const offB = subscribe(state, listener);
  try {
    offA();
    state.count++;
    await new Promise<void>(resolve => queueMicrotask(resolve));
    expect(calls).toBe(1);
  } finally {
    offA();
    offB();
  }
});
