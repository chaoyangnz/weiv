import assert from "node:assert/strict";
import { execFileSync } from "node:child_process";
import { mkdtempSync, writeFileSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join, resolve } from "node:path";
import { pathToFileURL } from "node:url";
import { build } from "vite";

const root = resolve(import.meta.dirname, "../..");
const binary = process.env.WEIV_BINARY_PATH || join(root, "zig-out/bin/weiv");
execFileSync(process.execPath, ["packages/weiv/scripts/build.mjs"], { cwd: root, stdio: "pipe" });
const { weiv } = await import("../../packages/weiv/dist/vite.mjs");
const temp = mkdtempSync(join(tmpdir(), "weiv-class-names-"));
const script = `
const Object=null; // Generated initialization must not capture this binding.
export let count=0, __proto__=0;
export let initial=class {static label=this.name};
export const {decl=class {static label=this.name; static read=()=>decl}}={};
export function run(){
  const results=[];
  function record(value,previous){
    const d=globalThis.Object.getOwnPropertyDescriptor(value,'name');
    results.push({name:typeof value.name==='function'?value.name():value.name,
      descriptor:{value:typeof d.value,writable:d.writable,enumerable:d.enumerable,configurable:d.configurable,get:typeof d.get},
      label:value.label,before:value.before,previous:value.previous===previous});
  }
  let previous=count;
  count=class {static label=this.name;static previous=count};record(count,previous);
  previous=count;
  ({count=class {static label=this.name;static previous=count}}={});record(count,previous);
  previous=count;
  count=class Inner {static label=this.name;static previous=count};record(count,previous);
  ({count=class {static name(){return 'method'};static label=typeof this.name}}={});record(count);
  ({value:count=class {static get name(){return 'getter'};static label=this.name}}={});record(count);
  count=class {static before=this.name;static name='';static label=this.name};record(count);
  const Base=class Base{};previous=count;
  count=class extends Base {static label=this.name;static previous=count};record(count,previous);
  count=0;count ||= class {static label=this.name};record(count);
  ({__proto__=class {static label=this.name}}=globalThis.Object.create(null));record(__proto__);
  count=class {static {globalThis.Object.defineProperty(this,'name',{value:'user',configurable:false})}static label=this.name};record(count);
  previous=count;try{count=class {static {throw new Error('class initializer')}}}catch(error){results.push({error:error.message,same:count===previous})}
  return {results,initial:{name:initial.name,label:initial.label},declaration:{name:decl.name,label:decl.label,same:decl.read()===decl}};
}
`;
try {
  const nativePath = join(temp, "native.mjs");
  writeFileSync(nativePath, script);
  const native = await import(pathToFileURL(nativePath));
  const expected = native.run();
  assert.equal(expected.results[0].name, "count");
  assert.equal(expected.results[5].before, "count");
  assert.equal(expected.results[8].name, "__proto__");
  const modulePath = join(temp, "managed.mjs");
  writeFileSync(modulePath, execFileSync(binary, ["emit", "module-cells", nativePath, "./publisher.mjs", JSON.stringify(["count", "__proto__", "decl", "initial"])], { cwd: root }));
  writeFileSync(join(temp, "publisher.mjs"), "import {createModuleState} from 'weiv:cells';export const moduleState=createModuleState();");
  const componentPath = join(temp, "Names.weiv");
  writeFileSync(componentPath, '<template><p>{{ typeof count }} / {{ decl.name }} / {{ typeof __proto__ }} / {{ initial.name }}</p><button @click="count=class {static label=this.name;static previous=count}">inline</button></template><script lang="ts">' + script + "\nwindow.addEventListener('names',event=>event.detail.result=run());window.addEventListener('names-read',event=>event.detail.result={name:count.name,label:count.label,previous:count.previous.name});</script>");
  writeFileSync(join(temp, "component.mjs"), execFileSync(binary, ["emit", "js", componentPath], { cwd: root, stdio: ["ignore", "pipe", "pipe"] }));
  const entry = join(temp, "entry.mjs");
  writeFileSync(entry, "export {run} from './managed.mjs';export {mount} from './component.mjs';");
  await build({ configFile: false, root: temp, logLevel: "silent", plugins: [weiv()], build: { target: "esnext", minify: false, outDir: join(temp, "vite"), lib: { entry, formats: ["es"], fileName: () => "names.mjs" } } });
  const builder = join(temp, "build.mjs");
  writeFileSync(builder, `import {weiv} from ${JSON.stringify(pathToFileURL(join(root, "packages/weiv/dist/bun.mjs")).href)};
    const result=await Bun.build({entrypoints:[${JSON.stringify(entry)}],outdir:${JSON.stringify(temp)},naming:'bun.mjs',plugins:[weiv()],target:'browser'});
    if(!result.success)throw new AggregateError(result.logs,'Class-name bundle failed');`);
  execFileSync("bun", [builder], { cwd: root, stdio: "pipe" });
  for (const [runner, output] of [["node", join(temp, "vite/names.mjs")], ["bun", join(temp, "bun.mjs")]]) {
    const check = join(temp, `check-${runner}.mjs`);
    writeFileSync(check, `import assert from 'node:assert/strict';
      import {JSDOM} from ${JSON.stringify(import.meta.resolve("jsdom"))};
      import {run,mount} from ${JSON.stringify(pathToFileURL(output).href)};
      const expected=${JSON.stringify(expected)};
      // JSON removes absent descriptor keys identically in the oracle and output.
      assert.deepEqual(JSON.parse(JSON.stringify(run())),expected);
      const dom=new JSDOM('<main></main>');globalThis.window=dom.window;globalThis.document=dom.window.document;
      const target=document.querySelector('main');const handle=mount(target,{});const detail={};
      window.dispatchEvent(new window.CustomEvent('names',{detail}));await new Promise(resolve=>queueMicrotask(resolve));
      assert.deepEqual(JSON.parse(JSON.stringify(detail.result)),expected);assert.equal(target.querySelector('p').textContent,'function / decl / function / initial');
      target.querySelector('button').dispatchEvent(new window.Event('click'));await new Promise(resolve=>queueMicrotask(resolve));
      const read={};window.dispatchEvent(new window.CustomEvent('names-read',{detail:read}));assert.deepEqual(read.result,{name:'count',label:'count',previous:'user'});
      handle.destroy();dom.window.close();`);
    execFileSync(runner, [check], { cwd: root, stdio: "pipe" });
  }
  console.log("Class named evaluation, descriptors, static order and outer references match Node's oracle in mounted and shared Vite/Bun output");
} finally {
  rmSync(temp, { recursive: true, force: true });
}
