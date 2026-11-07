import assert from "node:assert/strict";
import { execFileSync } from "node:child_process";
import { mkdtempSync, writeFileSync, rmSync, mkdirSync } from "node:fs";
import { tmpdir } from "node:os";
import { join, resolve } from "node:path";
import { pathToFileURL } from "node:url";
import { build } from "vite";

const root = resolve(import.meta.dirname, "../..");
const binary = process.env.WEIV_BINARY_PATH || join(root, "zig-out/bin/weiv");
const temp = mkdtempSync(join(tmpdir(), "weiv-helper-bindings-"));
const project = join(temp, "project");
mkdirSync(project);
try {
  writeFileSync(join(project, "timers.ts"), `
    export function setTimeout(callback:(value:number)=>unknown,value:number){return callback(value)}
    export function setInterval(callback:()=>unknown){return callback()}
    export function queueMicrotask(callback:()=>unknown){return callback()}
    export function requestAnimationFrame(callback:(value:number)=>unknown){return callback(7)}
  `);
  const component = join(project, "App.weiv");
  writeFileSync(component, `<template><p>{{ scope.n }} / {{ instance }} / {{ Array }} / {{ count }}</p>
    <button @click="(setTimeout(value=>{scope.n++;count+=value},1),setInterval(()=>{instance++;count++}),queueMicrotask(()=>{Array++;count++}),requestAnimationFrame(value=>count+=value))">go</button>
    </template><script lang="ts">
    import {setTimeout,setInterval,queueMicrotask,requestAnimationFrame} from './timers.ts';
    let scope={n:0};let instance=0;let Array=0;let count=0;
    async function advance(value,wait){count+=this.step;await wait;count+=value;return [this===holder,advance.name,advance.length]}
    const holder={step:2,advance};
    window.addEventListener('helper-async',event=>{event.detail.task=holder.advance(3,event.detail.wait)});
    </script>`);
  const output = join(temp, "app");
  execFileSync(binary, ["emit", "app", component, output], { cwd: root, stdio: "pipe" });
  const entry = join(output, "bundle.mjs");
  await build({ configFile: false, root: output, logLevel: "silent", build: { target: "esnext", minify: false, outDir: join(temp, "vite"), lib: { entry, formats: ["es"], fileName: () => "app.mjs" } } });
  const bunOutput = join(temp, "bun.mjs");
  execFileSync("bun", ["build", entry, "--outfile", bunOutput, "--target", "browser"], { cwd: root, stdio: "pipe" });
  for (const [label, runner, path] of [["direct", "node", entry], ["vite", "node", join(temp, "vite/app.mjs")], ["bun", "bun", bunOutput]]) {
    const check = join(temp, `check-${label}.mjs`);
    writeFileSync(check, `import assert from 'node:assert/strict';
      import {JSDOM} from ${JSON.stringify(import.meta.resolve("jsdom"))};
      import {mount} from ${JSON.stringify(pathToFileURL(path).href)};
      const dom=new JSDOM('<main></main>');globalThis.window=dom.window;globalThis.document=dom.window.document;
      const target=document.querySelector('main');const handle=mount(target,{});
      assert.equal(target.querySelector('p').textContent,'0 / 0 / 0 / 0');
      target.querySelector('button').click();assert.equal(target.querySelector('p').textContent,'0 / 0 / 0 / 0');
      await new Promise(resolve=>queueMicrotask(resolve));assert.equal(target.querySelector('p').textContent,'1 / 1 / 1 / 10');
      let release;const detail={wait:new Promise(resolve=>{release=resolve})};window.dispatchEvent(new window.CustomEvent('helper-async',{detail}));
      await new Promise(resolve=>queueMicrotask(resolve));assert.equal(target.querySelector('p').textContent,'1 / 1 / 1 / 12');
      release();assert.deepEqual(await detail.task,[true,'advance',2]);await new Promise(resolve=>queueMicrotask(resolve));assert.equal(target.querySelector('p').textContent,'1 / 1 / 1 / 15');
      handle.destroy();dom.window.close();`);
    execFileSync(runner, [check], { cwd: root, stdio: "pipe" });
  }
  console.log("Managed timers, shadowed state and async receiver/name/arity semantics hold directly and through Vite/Bun");
} finally {
  rmSync(temp, { recursive: true, force: true });
}
