import { expect, test } from "bun:test";
import { emitDirectBrowserModule, installJsdom, loadModules } from "./support";

async function mountContract() {
  const modules = await loadModules({
    "StateContract.mjs": emitDirectBrowserModule("test/examples/basic/state-contract.weiv"),
  });
  const previousWindow = (globalThis as any).window;
  const { document, window } = installJsdom();
  (globalThis as any).window = window;
  const target = document.createElement("div");
  document.body.append(target);
  const handle = modules["StateContract.mjs"].mount(target, {});
  return {
    read: (selector: string) => target.querySelector(selector)?.textContent,
    send: (type: string, detail: any = {}) => {
      window.dispatchEvent(new window.CustomEvent(type, { detail }));
      return detail;
    },
    close: () => {
      handle.destroy();
      window.close();
      (globalThis as any).window = previousWindow;
    },
  };
}

test("async writes notify before and after settlement", async () => {
  const fixture = await mountContract();
  try {
    let release!: () => void;
    const gate = new Promise<void>((resolve) => { release = resolve; });
    const detail = fixture.send("contract-async", { gate });
    expect(fixture.read(".scalar")).toBe("0");
    await new Promise<void>(resolve => queueMicrotask(resolve));
    expect(fixture.read(".scalar")).toBe("1");
    release();
    await detail.result;
    await new Promise<void>(resolve => queueMicrotask(resolve));
    expect(fixture.read(".scalar")).toBe("2");
  } finally { fixture.close(); }
});

test("detached promises notify without an update boundary", async () => {
  const fixture = await mountContract();
  try {
    fixture.send("contract-detached");
    await new Promise<void>((resolve) => queueMicrotask(resolve));
    expect(fixture.read(".scalar")).toBe("3");
  } finally { fixture.close(); }
});

test("rejected async writes notify and preserve rejection", async () => {
  const fixture = await mountContract();
  try {
    let reject!: (error: Error) => void;
    const gate = new Promise<void>((_, fail) => { reject = fail; });
    const detail = fixture.send("contract-async", { gate });
    const error = new Error("async contract failure");
    reject(error);
    await expect(detail.result).rejects.toBe(error);
    expect(fixture.read(".scalar")).toBe("2");
  } finally { fixture.close(); }
});

test("writes queue updates while synchronous exceptions propagate", async () => {
  const fixture = await mountContract();
  try {
    const error = new Error("contract failure");
    const detail = fixture.send("contract-throw", { error });
    expect(detail.caught).toBe(error);
    expect(fixture.read(".scalar")).toBe("0");
    await new Promise<void>(resolve => queueMicrotask(resolve));
    expect(fixture.read(".scalar")).toBe("4");
  } finally { fixture.close(); }
});

test("tracked object member writes notify without an external callback wrapper", async () => {
  const fixture = await mountContract();
  try {
    fixture.send("contract-object");
    expect(fixture.read(".object")).toBe("0");
    await new Promise<void>((resolve) => queueMicrotask(resolve));
    expect(fixture.read(".object")).toBe("2");
  } finally { fixture.close(); }
});
