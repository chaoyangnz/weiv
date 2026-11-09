import { expect, test } from "bun:test";
import { mkdtempSync, writeFileSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { pathToFileURL } from "node:url";
import { loadModules } from "./support";

const operations = [
  { id: "assign", initial: 0, body: "detail.result=(count=(detail.trace.push('rhs'),2));" },
  { id: "compound", initial: 0, body: "detail.result=(count+=(detail.trace.push('rhs'),2));" },
  { id: "or", initial: 0, body: "const first=(count||=(detail.trace.push('rhs'),3));detail.result=[first,(count||=(detail.trace.push('skipped'),99))];" },
  { id: "and", initial: 1, body: "const first=(count&&=(detail.trace.push('rhs'),3));count=0;detail.result=[first,(count&&=(detail.trace.push('skipped'),99))];" },
  { id: "nullish", initial: null, body: "const first=(count??=(detail.trace.push('rhs'),3));detail.result=[first,(count??=(detail.trace.push('skipped'),99))];" },
  { id: "prefix", initial: 1, body: "detail.result=++count;" },
  { id: "postfix", initial: 1, body: "detail.result=count++;" },
  { id: "object", initial: 0, body: "const rhs={get value(){detail.trace.push('get');return 4},length:9};const result=({[(detail.trace.push('key'),'value')]:count,...rest}=rhs);detail.result={same:result===rhs,length:rest.length};" },
  { id: "array", initial: 0, body: "const rhs=[undefined,9,6,7];const result=([count=(detail.trace.push('default'),5),,...rest]=rhs);detail.result={same:result===rhs,values:[...rest]};" },
  { id: "of", initial: 0, body: "for(count of [6,7])detail.trace.push('loop-'+count);detail.result=count;" },
  { id: "in", initial: 0, body: "for(count in {left:1,right:2})detail.trace.push(count);detail.result=count;" },
  { id: "replace", initial: 0, body: "const result=(state={n:8,extra:1});detail.result={same:result===state};state.n++;" },
  { id: "member", initial: 0, body: "detail.result=state.n++;state.extra=7;" },
  { id: "delete", initial: 0, body: "detail.result=delete state.extra;" },
  { id: "callable", initial: 0, body: "read=()=>count+1;detail.result=read();" },
  { id: "partial", initial: 0, body: "try{({value:count,missing:state.n}={get value(){detail.trace.push('get');return 9},get missing(){detail.trace.push('throw');throw Error('rhs')}})}catch(error){detail.result=error.message}" },
  { id: "receiver", initial: 0, body: "count++;detail.result=this===detail.receiver;" },
] as const;

const contexts = ["direct", "dom", "inline", "external", "timeout", "interval", "microtask", "frame", "promise", "rejected", "finally", "async"] as const;
const tick = () => new Promise<void>(resolve => queueMicrotask(resolve));
function deferred() {
  let resolve!: (value?: any) => void, reject!: (error: any) => void;
  const promise = new Promise<any>((yes, no) => { resolve = yes; reject = no; });
  return { promise, resolve, reject };
}

const storage = `let count=0;let state={n:0,extra:0};let rest=[];let read=()=>count;
function matrixReset(initial){count=initial===null?null:Number(initial);state={n:0,extra:0};rest=[];read=()=>count;}
function matrixSnapshot(){const show=value=>value==null?'':String(value);return [show(count),show(state.n),show(state.extra),String(rest.length),show(read())].join('|');}
function matrixComplete(detail){detail.resolve({result:detail.result,trace:detail.trace});}
`;

test("supported writes preserve native semantics across the mounted callback matrix", async () => {
  const dir = mkdtempSync(join(tmpdir(), "weiv-cells-matrix-"));
  try {
  const path = join(dir, "Matrix.weiv");
  let script = storage;
  let template = '<p>{{ count }}|{{ state.n }}|{{ state.extra }}|{{ rest.length }}|{{ read() }}</p>';
  const exposed: string[] = [];
  for (const operation of operations) {
    const { id, body } = operation;
    script += `function matrix_${id}(detail){${body}matrixComplete(detail);}\n`;
    script += `function matrix_dom_${id}(event){const detail=event.detail;try{${body}matrixComplete(detail)}catch(error){detail.reject(error)}}\n`;
    script += `window.addEventListener('matrix-external-${id}',matrix_dom_${id});\n`;
    template += `<button id="dom-${id}" @click="matrix_dom_${id}">named</button>`;
    template += `<button id="inline-${id}" @click="(()=>{const detail=event.detail;try{${body}matrixComplete(detail)}catch(error){detail.reject(error)}})()">inline</button>`;
    exposed.push(`${JSON.stringify(`direct-${id}`)}:matrix_${id}`);
    const callback = `()=>{try{${body}matrixComplete(detail)}catch(error){detail.reject(error)}}`;
    const dispatchers = {
      timeout: `setTimeout(${callback},0)`,
      interval: `const timer=setInterval(()=>{clearInterval(timer);(${callback})()},0)`,
      microtask: `queueMicrotask(${callback})`,
      frame: `requestAnimationFrame(${callback})`,
      promise: `Promise.resolve().then(${callback})`,
      rejected: `Promise.reject('expected').catch(${callback})`,
      finally: `Promise.resolve().finally(${callback})`,
    };
    for (const [context, source] of Object.entries(dispatchers)) {
      script += `function matrix_${context}_${id}(detail){${source};}\n`;
      exposed.push(`${JSON.stringify(`${context}-${id}`)}:matrix_${context}_${id}`);
    }
    script += `async function matrix_async_${id}(detail){await detail.first;${body}detail.wrote();await detail.second;matrixComplete(detail);}\n`;
    exposed.push(`${JSON.stringify(`async-${id}`)}:matrix_async_${id}`);
  }
  script += `window.addEventListener('matrix-api',event=>{event.detail.api={reset:matrixReset,cases:{${exposed.join(',')}}};});`;
  writeFileSync(path, `<template>${template}</template><script lang="ts">${script}</script>`);
  const oracle = new Function(`"use strict";${storage}${operations.map(({ id, body }) => `function oracle_${id}(detail){${body}matrixComplete(detail);}`).join('\n')}return {reset:matrixReset,snapshot:matrixSnapshot,actions:{${operations.map(({ id }) => `${JSON.stringify(id)}:oracle_${id}`).join(',')}}};`)();
  const compiled = Bun.spawnSync(["cyna-out/bin/weiv", "--json-diagnostics", "emit", "js", path], { stdout: "pipe", stderr: "pipe" });
  if (compiled.exitCode) throw new Error(new TextDecoder().decode(compiled.stderr));
  const diagnostics = new TextDecoder().decode(compiled.stderr);
  // These intentionally effectful getter/iterator inputs may retain boundary
  // warnings; unsupported/unresolved internal emission must never be hidden.
  const warnings = diagnostics.trim() ? JSON.parse(diagnostics).diagnostics : [];
  for (const warning of warnings) {
    expect(warning.code).toBe("reactivity.unverified_dependency");
    expect(warning.severity).toBe("warning");
    expect(warning.fatal).toBe(false);
    expect(warning.sourcePath).toBe(path);
    expect(warning.span.start).toBeGreaterThanOrEqual(0);
    expect(warning.message).toContain("observable or subscription adapter");
  }
  const runtime = pathToFileURL(join(process.cwd(), "packages/weiv/src/runtime/cell.ts")).href;
  const code = new TextDecoder().decode(compiled.stdout).replace('"weiv:cells"', JSON.stringify(runtime));
  const modules = await loadModules({ "Matrix.mjs": code });
  const { JSDOM } = require("jsdom");
  const dom = new JSDOM("<main></main>", { pretendToBeVisual: true });
  const previous = { window: globalThis.window, document: globalThis.document, requestAnimationFrame: globalThis.requestAnimationFrame };
  Object.assign(globalThis, { window: dom.window, document: dom.window.document, requestAnimationFrame: dom.window.requestAnimationFrame.bind(dom.window) });
  const target = dom.window.document.querySelector("main");
  const handle = modules["Matrix.mjs"].mount(target, {});
  try {
    const request: any = {};
    dom.window.dispatchEvent(new dom.window.CustomEvent("matrix-api", { detail: request }));
    const api = request.api;
    let jobs = 0;
    const update = handle.instance.updateDirty;
    handle.instance.updateDirty = (...args: any[]) => { jobs++; return update(...args); };
    for (const context of contexts) for (const operation of operations) {
      const label = `${context}/${operation.id}`;
      oracle.reset(operation.initial);
      let expected: any;
      const native = { trace: [], receiver: oracle.actions, resolve: (value: any) => { expected = value; } };
      oracle.actions[operation.id].call(native.receiver, native);
      const expectedText = oracle.snapshot();
      api.reset(operation.initial);
      await tick();
      jobs = 0;
      const done = deferred(), first = deferred(), second = deferred(), wrote = deferred();
      let settled = false;
      const completion = done.promise.then(value => { settled = true; return value; });
      const detail: any = { trace: [], resolve: done.resolve, reject: done.reject, first: first.promise, second: second.promise, wrote: wrote.resolve,
        receiver: context === "external" ? dom.window : context === "dom" || context === "inline" ? undefined : api.cases };
      if (context === "dom" || context === "inline") {
        target.querySelector(`#${context}-${operation.id}`).dispatchEvent(new dom.window.CustomEvent("click", { detail }));
      } else if (context === "external") dom.window.dispatchEvent(new dom.window.CustomEvent(`matrix-external-${operation.id}`, { detail }));
      else {
        const task = api.cases[`${context}-${operation.id}`](detail);
        if (task && typeof task.then === "function") task.catch(done.reject);
      }
      if (context === "async") {
        expect(settled, label).toBe(false);
        first.resolve();
        await Promise.race([wrote.promise, completion.then(() => { throw new Error(`${label}: completed before second await`); })]);
        await tick();
        expect(target.querySelector("p").textContent, label).toBe(expectedText);
        expect(settled, label).toBe(false);
        second.resolve();
      }
      const actual = await completion;
      await tick();
      expect(actual, label).toEqual(expected);
      expect(target.querySelector("p").textContent, label).toBe(expectedText);
      expect(jobs, label).toBe(1);
    }
  } finally {
    handle.destroy();dom.window.close();Object.assign(globalThis, previous);
  }
  } finally { rmSync(dir, { recursive: true, force: true }); }
}, 60000);
