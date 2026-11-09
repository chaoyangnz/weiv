import assert from "node:assert/strict";
import { execFileSync } from "node:child_process";
import { mkdtempSync, mkdirSync, writeFileSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join, resolve } from "node:path";
import { pathToFileURL } from "node:url";
import { build } from "vite";

const root = resolve(import.meta.dirname, "../..");
const binary = process.env.WEIV_BINARY_PATH || join(root, "cyna-out/bin/weiv");
execFileSync(process.execPath, ["packages/weiv/scripts/build.mjs"], { cwd: root, stdio: "pipe" });
const { weiv } = await import("../../packages/weiv/dist/vite.mjs");
const temp = mkdtempSync(join(tmpdir(), "weiv-module-cells-"));
const source = `
export let count=0;
export let multi=0, before=multi++, after=++multi;
export let state={count:0};
export let fn=()=>0;
export const cls=class {static label=this.name};
export const firstName=fn.name;
export function increment(){return count++}
export function prefix(){return ++count}
export function replace(){return state={count:10}}
export function replaceFunction(){return fn=function(){}}
export function fail(){count=(()=>{throw Error('rhs')})()}
export function logical(){return state ||= {count:99}}
export function combined(){return (count=1)+(count+=2)}
export async function later(){return count=await Promise.resolve(9)}
export {count as live};
export default count;
export let other=0, rest=[]; let __proto__=0;
export function patterns(){
  const trace=[];const rhs={get a(){trace.push('get');return 4},nested:{value:5},tail:6};
  const result=({[(trace.push('key'),'a')]:count,nested:{value:other},...rest}=rhs);
  const array=[7,undefined,9,10];const returned=([count,other=(trace.push('default'),8),...rest]=array);
  for([count] of [[11],[12]])trace.push('loop-'+count);
  for(other in {first:1,last:2})trace.push(other);
  const target={};({value:target.count,count}={value:1,count:13});
  return {trace,same:result===rhs&&returned===array,count,other,rest:[...rest],member:target.count};
}
export function partial(){
  const trace=[];
  try{({count,other}={get count(){trace.push('first');return 14},get other(){trace.push('throw');throw Error('getter')}})}catch(error){trace.push(error.message)}
  const input={[Symbol.iterator](){let step=0;return {next(){trace.push('next');return {done:false,value:++step===1?15:undefined}},return(){trace.push('close');return {done:true}}}}};
  try{[count,other=(()=>{throw Error('default')})()]=input}catch(error){trace.push(error.message)}
  return {trace,count,other};
}
export function patternReplace(raw){return ({state}=raw)}
export function defaultNames(){
  ({fn=()=>fn}={});const previous=fn;
  ({value:fn=class {static label=this.name;static previous=fn}}={});
  ({__proto__=function(){}}=Object.create(null));
  return {name:fn.name,label:fn.label,previous:fn.previous===previous,proto:__proto__.name};
}
export const declarationTrace=[];
const declarationSource={get first(){declarationTrace.push('first');return 1},get next(){declarationTrace.push('next-'+declCount);return undefined},tail:3};
export let {first:declCount,[(declarationTrace.push('key-'+declCount),'next')]:declOther=declCount+1,...declRest}=declarationSource;
export const [declState,,...declRows]=[{n:4},99,{n:5},{n:6}];
export const {declFn=()=>declCount,declClass=class {static label=this.name;static before=declFn.name}}={};
export function declarationUpdate(){declCount++;declState.n++;declRows[0].n++;declRest.tail++;return {trace:[...declarationTrace],count:declCount,other:declOther,n:declState.n,rows:declRows.map(x=>x.n),tail:declRest.tail}}
`;
function compile(source, names) {
  const path = join(temp, "source.mjs");
  writeFileSync(path, source);
  return execFileSync(binary, ["emit", "module-cells", path, "./publisher.mjs", JSON.stringify(names)], { cwd: root, encoding: "utf8" });
}
try {
  const code = compile(source, ["count", "state", "fn", "cls", "multi", "other", "rest", "__proto__", "declCount", "declRest", "declState", "declRows", "declFn", "declClass"]);
  writeFileSync(join(temp, "managed.mjs"), code);
  writeFileSync(join(temp, "publisher.mjs"), `import {createModuleState} from 'weiv:cells'; export const moduleState=createModuleState();`);
  writeFileSync(join(temp, "consumer.mjs"), `export {state as secondState} from './managed.mjs';`);
  const entry = join(temp, "entry.mjs");
  writeFileSync(entry, `export * as managed from './managed.mjs'; export * from './consumer.mjs'; export {moduleState} from './publisher.mjs'; export {createCellScope} from 'weiv:cells';`);
  const native = await import(pathToFileURL(join(temp, "source.mjs")));
  await build({configFile:false, root:temp, logLevel:'silent', plugins:[weiv()], build:{target:'esnext',outDir:join(temp,'vite'), minify:false, lib:{entry, formats:['es'], fileName:()=> 'result.mjs'}}});
  const runner = join(temp, 'build.mjs');
  writeFileSync(runner, `import {weiv} from ${JSON.stringify(pathToFileURL(join(root,'packages/weiv/dist/bun.mjs')).href)};
    const result=await Bun.build({entrypoints:[${JSON.stringify(entry)}],outdir:${JSON.stringify(temp)},naming:'bun.mjs',plugins:[weiv()],target:'browser'});
    if(!result.success) throw new AggregateError(result.logs,'Managed module bundle failed');`);
  execFileSync('bun', [runner], {cwd:root, stdio:'pipe'});
  for (const [runner, output] of [["node", join(temp,'vite/result.mjs')], ["bun",join(temp,'bun.mjs')]]) {
    const check=join(temp,`check-${runner}.mjs`);
    writeFileSync(check, `
import assert from 'node:assert/strict';
import {managed as m, secondState, moduleState, createCellScope} from ${JSON.stringify(pathToFileURL(output).href)};
import * as native from ${JSON.stringify(pathToFileURL(join(temp,'source.mjs')).href)};
assert.deepEqual(Object.keys(m).sort(), ${JSON.stringify(Object.keys(native).sort())});
assert.equal(m.state,secondState);
assert.equal(m.fn.name,'fn'); assert.equal(m.firstName,'fn');
assert.equal(m.cls.name,'cls'); assert.equal(m.cls.label,'cls');
assert.equal(m.multi,2); assert.equal(m.before,0); assert.equal(m.after,2);
const updates=[]; const scope=createCellScope(dirty=>updates.push([...dirty]));
scope.watch(moduleState.getCell('count'),'count'); scope.watch(moduleState.getCell('state'),'state');
scope.watch(moduleState.getCell('declCount'),'declCount');scope.watch(moduleState.getCell('declState'),'declState');
assert.deepEqual(m.declarationUpdate(),native.declarationUpdate());
assert.equal(m.declFn.name,'declFn');assert.equal(m.declClass.name,'declClass');assert.equal(m.declClass.label,'declClass');assert.equal(m.declClass.before,'declFn');
assert.equal(m.increment(),0); assert.equal(m.prefix(),2); assert.equal(m.live,2); assert.equal(m.default,0);
await new Promise(resolve=>queueMicrotask(resolve)); assert.equal(updates.length,1);
const replacement=m.replace(); assert.equal(replacement,m.state); replacement.count++;
await new Promise(resolve=>queueMicrotask(resolve)); assert.equal(updates.length,2);
assert.equal(m.logical(),replacement); assert.equal(m.state.count,11);
await new Promise(resolve=>queueMicrotask(resolve)); assert.equal(updates.length,2);
assert.throws(()=>m.fail(),/rhs/); await new Promise(resolve=>queueMicrotask(resolve)); assert.equal(updates.length,2);
assert.equal(m.replaceFunction().name,'fn');
assert.equal(m.combined(),4); assert.equal(m.live,3);
await m.later(); assert.equal(m.live,9);
await new Promise(resolve=>queueMicrotask(resolve));
assert.deepEqual(m.patterns(),native.patterns());assert.equal(m.live,13);
await new Promise(resolve=>queueMicrotask(resolve));const beforePartial=updates.length;
assert.deepEqual(m.partial(),native.partial());assert.equal(m.live,15);
await new Promise(resolve=>queueMicrotask(resolve));assert.equal(updates.length,beforePartial+1);
const old=m.state;const raw={state:{count:20}};
assert.equal(m.patternReplace(raw),raw);assert.notEqual(m.state,raw.state);assert.equal(m.state,secondState);
await new Promise(resolve=>queueMicrotask(resolve));const afterReplace=updates.length;
old.count++;await new Promise(resolve=>queueMicrotask(resolve));assert.equal(updates.length,afterReplace);
m.state.count++;await new Promise(resolve=>queueMicrotask(resolve));assert.equal(updates.length,afterReplace+1);
assert.deepEqual(m.defaultNames(),native.defaultNames());
scope.dispose();
`);
    execFileSync(runner,[check],{cwd:root,stdio:'pipe'});
  }

  // A real ESM cycle subscribes and calls the source writer before its lexical
  // declaration initializes. RHS effects precede the TDZ error; no write publishes.
  const runtime = pathToFileURL(join(root, 'packages/weiv/dist/runtime/cell.js')).href;
  writeFileSync(join(temp, 'publisher.mjs'), `import {createModuleState} from ${JSON.stringify(runtime)}; export const moduleState=createModuleState();`);
  const cyclic = compile(`import './early.mjs'; export let count=0; export function set(next){return count=next()} export function pattern(next){return ({count}=next())}`, ['count']);
  writeFileSync(join(temp, 'cyclic.mjs'), cyclic.replaceAll('"weiv:cells"', JSON.stringify(runtime)));
  writeFileSync(join(temp, 'early.mjs'), `
    import {set,pattern} from './cyclic.mjs'; import {moduleState} from './publisher.mjs';
    import {createCellScope} from ${JSON.stringify(runtime)};
    export const events=[]; export let updates=0;
    export const scope=createCellScope(()=>{updates++}); scope.watch(moduleState.getCell('count'),'count');
    try {set(()=>{events.push('rhs');return 1})} catch(error){events.push(error.name)}
    try {pattern(()=>{events.push('pattern-rhs');return {get count(){events.push('pattern-get');return 2}}})} catch(error){events.push(error.name)}
  `);
  const cycle = await import(pathToFileURL(join(temp, 'cyclic.mjs')));
  const early = await import(pathToFileURL(join(temp, 'early.mjs')));
  assert.deepEqual(early.events, ['rhs','ReferenceError','pattern-rhs','pattern-get','ReferenceError']);
  await new Promise(resolve=>queueMicrotask(resolve));
  assert.equal(early.updates, 1);
  assert.equal(cycle.set(()=>3),3);
  await new Promise(resolve=>queueMicrotask(resolve));
  assert.equal(early.updates, 2);
  early.scope.dispose();

  // Keep initialized exports live even when a later binding fails. Cleanup must
  // see the initialized earlier export and preserve the original thrown error.
  const declarationSetup=`import {events} from './early.mjs';
    export function read(){return count} export function readLater(){return pending}
    const input={[Symbol.iterator](){events.push('iterator');let step=0;return {
      next(){events.push('next');return {done:false,value:++step===1?{n:1}:undefined}},
      return(){events.push('return-'+count.n);throw Error('close')}
    }}};`;
  const failures=[
    {name:'default',source:`export let [count,pending=(()=>{events.push('default-'+count.n);throw Error('default')})()]=input;`,names:['count','pending'],error:/default/,events:['iterator','next','next','default-1','return-1']},
    {name:'close',source:`export let [count]=input;`,names:['count'],error:/close/,events:['iterator','next','return-1']},
    {name:'empty',source:`export let {count,missing:{}}={count:{n:1},missing:null};`,names:['count'],error:TypeError,events:[]},
    {name:'mixed',source:`export let count={n:1},[pending=(()=>{throw Error('default')})()]=[undefined];`,names:['count','pending'],error:/default/,events:[]},
  ];
  for(const failure of failures)for(const mode of ['native','managed']){
    const dir=join(temp,'failure-'+failure.name+'-'+mode);mkdirSync(dir);
    const registry='weiv-declaration-'+dir;
    writeFileSync(join(dir,'publisher.mjs'),`import {createModuleState} from ${JSON.stringify(runtime)};export const moduleState=createModuleState();`);
    const source=declarationSetup+failure.source;
    const text=mode==='managed'?compile(source,failure.names).replaceAll('"weiv:cells"',JSON.stringify(runtime)):source;
    writeFileSync(join(dir,'subject.mjs'),text);
    writeFileSync(join(dir,'early.mjs'),`import {read,readLater} from './subject.mjs';export {read,readLater};
      import {moduleState} from './publisher.mjs';export {moduleState};
      import {createCellScope} from ${JSON.stringify(runtime)};
      export const events=[];export let updates=0;export const scope=createCellScope(()=>updates++);scope.watch(moduleState.getCell('count'),'count');
      globalThis[${JSON.stringify(registry)}]={read,readLater,moduleState,scope,events,get updates(){return updates}};`);
    await assert.rejects(import(pathToFileURL(join(dir,'subject.mjs'))),failure.error);
    const early=globalThis[registry];assert(early);delete globalThis[registry];
    assert.deepEqual(early.events,failure.events);
    assert.equal(early.read().n,1);assert.throws(()=>early.readLater(),ReferenceError);
    await new Promise(resolve=>queueMicrotask(resolve));
    assert.equal(early.updates,mode==='managed'?1:0);
    if(mode==='managed'){
      assert.equal(early.moduleState.getCell('count').value,early.read());
      early.read().n++;await new Promise(resolve=>queueMicrotask(resolve));assert.equal(early.updates,2);
    }
    early.scope.dispose();
  }
  const awaited=join(temp,'awaited');mkdirSync(awaited);
  writeFileSync(join(awaited,'publisher.mjs'),`import {createModuleState} from ${JSON.stringify(runtime)};export const moduleState=createModuleState();`);
  writeFileSync(join(awaited,'subject.mjs'),compile('export let {count}=await Promise.resolve({count:2});',['count']).replaceAll('"weiv:cells"',JSON.stringify(runtime)));
  const awaitedModule=await import(pathToFileURL(join(awaited,'subject.mjs')));
  const awaitedPublisher=await import(pathToFileURL(join(awaited,'publisher.mjs')));
  assert.equal(awaitedModule.count,2);assert.equal(awaitedPublisher.moduleState.getCell('count').value,2);
  console.log("Managed module ESM exports, identity, names, writes and notifications pass under Vite/Node and Bun");
} finally { rmSync(temp,{recursive:true,force:true}); }
