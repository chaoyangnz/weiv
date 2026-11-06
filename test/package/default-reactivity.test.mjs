import assert from "node:assert/strict";
import { execFileSync } from "node:child_process";
import { mkdtempSync, writeFileSync, readFileSync, rmSync, symlinkSync, mkdirSync, realpathSync } from "node:fs";
import { tmpdir } from "node:os";
import { join, resolve } from "node:path";
import { pathToFileURL } from "node:url";
import { build, createServer } from "vite";

const repo = resolve(import.meta.dirname, "../..");
const binary = join(repo, "zig-out/bin/weiv");
execFileSync(process.execPath, ["packages/weiv/scripts/build.mjs"], { cwd: repo, stdio: "pipe" });
const { weiv } = await import("../../packages/weiv/dist/vite.mjs");
const temp = realpathSync(mkdtempSync(join(tmpdir(), "weiv-default-reactivity-")));
const project = join(temp, "project");mkdirSync(project);
let server;
try {
  writeFileSync(join(project, "state.ts"), `export let left=0,right=0;export let state={count:0};export function advance(){left++;right++;state.count++}export function replace(){state={count:10}}`);
  symlinkSync("state.ts", join(project, "state-alias.ts"));
  for (const [name, binding, source] of [["Left", "left", "state.ts"], ["Right", "right", "state-alias.ts"]]) {
    writeFileSync(join(project, `${name}.weiv`), `<template><p>${name}:{{ ${binding} }}/{{ state.count }}/{{ local }}</p><button @click="increment">local</button></template><script lang="ts">import {${binding},state} from './${source}';let local=0;function increment(){local++}window.addEventListener('local-tick',()=>local++);window.addEventListener('read-${name}',event=>event.detail.state=state);</script><style>p{color:rebeccapurple}</style>`);
  }
  const entry = join(project, "entry.ts");
  // The ordinary JS consumer is intentionally encountered before either component.
  writeFileSync(entry, `export * as source from './state.ts';export {observable} from 'weiv:observable';export {mount as mountLeft} from './Left.weiv';export {mount as mountRight} from './Right.weiv';`);
  const viteOutput = join(temp, "vite");
  await build({ configFile: false, root: project, logLevel: "silent", plugins: [weiv()], build: { target: "esnext", minify: false, outDir: viteOutput, lib: { entry, formats: ["es"], fileName: () => "app.mjs" } } });
  const bunOutput = join(temp, "bun.mjs");
  const builder = join(temp, "build.mjs");
  writeFileSync(builder, `import {weiv} from ${JSON.stringify(pathToFileURL(join(repo, "packages/weiv/dist/bun.mjs")).href)};const result=await Bun.build({entrypoints:[${JSON.stringify(entry)}],outdir:${JSON.stringify(temp)},naming:'bun.mjs',target:'browser',plugins:[weiv()]});if(!result.success)throw new AggregateError(result.logs,'Default managed Bun build failed');`);
  execFileSync("bun", [builder], { cwd: project, env: { ...process.env, WEIV_BINARY_PATH: binary }, stdio: "pipe" });
  for (const [runner, output] of [["node", join(viteOutput, "app.mjs")], ["bun", bunOutput]]) {
    const check = join(temp, `check-${runner}.mjs`);
    writeFileSync(check, `import assert from 'node:assert/strict';import {JSDOM} from ${JSON.stringify(import.meta.resolve("jsdom"))};import {source,observable,mountLeft,mountRight} from ${JSON.stringify(pathToFileURL(output).href)};
      const dom=new JSDOM('<main><section id="left"></section><section id="right"></section></main>');globalThis.window=dom.window;globalThis.document=dom.window.document;
      const a=document.querySelector('#left'),b=document.querySelector('#right');const left=mountLeft(a,{}),right=mountRight(b,{});const tick=()=>new Promise(resolve=>queueMicrotask(resolve));
      assert.equal(left.instance.cellManaged,true);assert.equal(right.instance.cellManaged,true);assert.deepEqual(Object.keys(source).sort(),['advance','left','replace','right','state']);assert.equal(typeof source.left,'number');assert.equal(observable(source.state),source.state);
      for(const name of ['Left','Right']){const detail={};window.dispatchEvent(new window.CustomEvent('read-'+name,{detail}));assert.equal(detail.state,source.state)}
      source.advance();assert.equal(a.querySelector('p').textContent,'Left:0/0/0');await tick();assert.equal(a.querySelector('p').textContent,'Left:1/1/0');assert.equal(b.querySelector('p').textContent,'Right:1/1/0');
      window.dispatchEvent(new window.Event('local-tick'));await tick();assert.equal(a.querySelector('p').textContent,'Left:1/1/1');assert.equal(b.querySelector('p').textContent,'Right:1/1/1');
      const old=source.state;source.replace();await tick();assert.equal(a.querySelector('p').textContent,'Left:1/10/1');assert.equal(b.querySelector('p').textContent,'Right:1/10/1');old.count++;await tick();assert.equal(a.querySelector('p').textContent,'Left:1/10/1');
      left.destroy();source.advance();await tick();assert.equal(a.textContent,'');assert.equal(b.querySelector('p').textContent,'Right:2/11/1');right.destroy();dom.window.close();`);
    execFileSync(runner, [check], { cwd: project, stdio: "pipe" });
  }

  const managed = execFileSync(binary, ["emit", "js", join(project, "Left.weiv")], { cwd: repo, encoding: "utf8", stdio: "pipe" });
  const legacy = execFileSync(binary, ["emit", "js-legacy", join(project, "Left.weiv")], { cwd: repo, encoding: "utf8", stdio: "pipe" });
  assert(managed.includes("const __weiv_cellManaged = true"));assert(legacy.includes("const __weiv_cellManaged = false"));
  execFileSync(process.execPath, [join(repo, "packages/weiv/bin/weiv.mjs"), "emit", "app", join(project, "Left.weiv"), join(temp, "cli")], { cwd: project, env: { ...process.env, WEIV_BINARY_PATH: binary }, stdio: "pipe" });
  assert(readFileSync(join(temp, "cli/Left.mjs"), "utf8").includes("const __weiv_cellManaged = true"));

  // Existing application smoke: keep its source unchanged under the new default.
  const todoOutput = join(temp, 'todomvc');
  execFileSync(binary, ['emit', 'app', join(repo, 'test/examples/todomvc/App.weiv'), todoOutput], { cwd: repo, stdio: 'pipe' });
  const todoCheck = join(temp, 'check-todomvc.mjs');
  writeFileSync(todoCheck, `import assert from 'node:assert/strict';import {JSDOM} from ${JSON.stringify(import.meta.resolve('jsdom'))};import {mount} from ${JSON.stringify(pathToFileURL(join(todoOutput, 'bundle.mjs')).href)};
    const dom=new JSDOM('<main></main>');globalThis.window=dom.window;globalThis.document=dom.window.document;
    const target=document.querySelector('main');const handle=mount(target,{title:'Managed TodoMVC'});const tick=()=>new Promise(resolve=>queueMicrotask(resolve));
    assert.equal(target.querySelectorAll('.todo-list > li').length,5);const input=target.querySelector('.newtodo');input.value='Migrate without wrappers';input.dispatchEvent(new window.KeyboardEvent('keydown',{key:'Enter',bubbles:true}));await tick();
    assert.equal(target.querySelectorAll('.todo-list > li').length,6);assert(target.textContent.includes('Migrate without wrappers'));
    const first=target.querySelector('.todo-list > li');first.querySelector('.destroy').click();await tick();assert.equal(target.querySelectorAll('.todo-list > li').length,5);
    handle.destroy();dom.window.close();`);
  execFileSync(process.execPath, [todoCheck], { cwd: project, stdio: 'pipe' });

  const legacyOutput = join(temp, 'legacy');
  await build({ configFile: false, root: project, logLevel: 'silent', plugins: [weiv({ reactivity: 'legacy' })], build: { target: 'esnext', minify: false, outDir: legacyOutput, lib: { entry, formats: ['es'], fileName: () => 'legacy.mjs' } } });
  assert(readFileSync(join(legacyOutput, 'legacy.mjs'), 'utf8').includes('const __weiv_cellManaged = false'));
  writeFileSync(builder, `import {weiv} from ${JSON.stringify(pathToFileURL(join(repo, 'packages/weiv/dist/bun.mjs')).href)};const result=await Bun.build({entrypoints:[${JSON.stringify(entry)}],outdir:${JSON.stringify(temp)},naming:'bun-legacy.mjs',target:'browser',plugins:[weiv({reactivity:'legacy'})]});if(!result.success)throw new AggregateError(result.logs,'Legacy Bun build failed');`);
  execFileSync('bun', [builder], { cwd: project, env: { ...process.env, WEIV_BINARY_PATH: binary }, stdio: 'pipe' });
  const legacyCheck = join(temp, 'check-legacy.mjs');
  writeFileSync(legacyCheck, `import assert from 'node:assert/strict';import {JSDOM} from ${JSON.stringify(import.meta.resolve('jsdom'))};import {mountLeft} from ${JSON.stringify(pathToFileURL(join(temp, 'bun-legacy.mjs')).href)};
    const dom=new JSDOM('<main></main>');globalThis.window=dom.window;globalThis.document=dom.window.document;const target=document.querySelector('main');const handle=mountLeft(target,{});
    assert.equal(handle.instance.cellManaged,false);target.querySelector('button').click();assert.equal(target.querySelector('p').textContent,'Left:0/0/1');handle.destroy();dom.window.close();`);
  execFileSync('bun', [legacyCheck], { cwd: project, stdio: 'pipe' });

  // Development serves the same graph and rebuilds it when shared source changes.
  writeFileSync(join(project, "index.html"), '<script type="module" src="/entry.ts"></script>');
  server = await createServer({ configFile: false, root: project, logLevel: "silent", plugins: [weiv()], server: { middlewareMode: true } });
  const first = await server.transformRequest('/Left.weiv');assert(first.code.includes('export * from'));
  const cached = /export \* from "([^"]+)"/.exec(first.code)[1];
  const native = await server.transformRequest(cached.startsWith('/@fs/') ? cached : `/@fs${cached}`);assert(native.code.includes('__weiv_cellManaged = true'));
  const reloaded = new Promise((resolve, reject) => {
    const timer = setTimeout(() => reject(new Error('Shared-state edit did not rebuild/reload the managed dev graph')), 5000);
    const send = server.ws.send.bind(server.ws);
    server.ws.send = (...args) => { if (args[0]?.type === 'full-reload') { clearTimeout(timer);resolve(); } return send(...args); };
  });
  writeFileSync(join(project, 'state.ts'), readFileSync(join(project, 'state.ts'), 'utf8').replace('left++', 'left+=2'));
  await reloaded;

  console.log("Default CLI/Vite/Bun preserve shared state, async DOM, existing TodoMVC, legacy opt-out and development graph reloads");
} finally {
  await server?.close();rmSync(temp, { recursive: true, force: true });
}
