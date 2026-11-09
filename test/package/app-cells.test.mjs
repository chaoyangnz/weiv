import assert from 'node:assert/strict';
import {execFileSync,spawnSync} from 'node:child_process';
import {mkdtempSync, mkdirSync, writeFileSync, readFileSync, readdirSync, symlinkSync, rmSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {join, resolve} from 'node:path';
import {pathToFileURL} from 'node:url';
import {JSDOM} from 'jsdom';
import {build} from 'vite';

const root=resolve(import.meta.dirname,'../..');
const binary=process.env.WEIV_BINARY_PATH || join(root,'cyna-out/bin/weiv');
const temp=mkdtempSync(join(tmpdir(),'weiv-app-cells-'));
const project=join(temp,'project'), output=join(temp,'dist');
mkdirSync(project);
function file(name,source){writeFileSync(join(project,name),source)}
const tick=()=>new Promise(resolve=>queueMicrotask(resolve));
let dom,handle;
const previous={window:globalThis.window,document:globalThis.document};
try {
  file('parameter-factory.ts', `const factoryRaw=new Map(); export function makeParameter(value){const forwarded=value;return {item:forwarded,read:()=>value.count}} export function maximum(args){return Math.max(...args)} export function serialize(args){return JSON.stringify(...args)} export function oneArgument(value){return [value]} export function invoke(callback,value){return callback(value)} export function invokeMethod(value,key){return value[key]()}`);
  file('store.ts', `
    import {snapshot} from 'weiv:observable';
    import {makeParameter,maximum,serialize,oneArgument,invoke,invokeMethod} from './parameter-factory';
    import * as factory from './parameter-factory';
    const factoryRaw={count:0}; let factoryCount=0;
    let conversionCount=0;
    const numericValue={valueOf:()=>conversionCount};
    const jsonValue={toJSON:()=>({count:conversionCount})};
    export function spreadNumber(){return maximum(factory.oneArgument(numericValue))}
    export function spreadJson(){return serialize(oneArgument(jsonValue))}
    export function callbackNumber(){return invoke(value=>value.count,factoryRaw)}
    export function callbackJson(){return invoke(value=>({toJSON:key=>({count:value.count,key:key?'child':'root'})}),factoryRaw)}
    const methodState={count:0,read(){return [{valueOf:()=>this.count}]}};
    export function callbackMethod(){return Math.max(...invokeMethod(methodState,'read'))}
    export const conversionView={toString:()=>String(conversionCount),valueOf:()=>conversionCount};
    function makeFactoryView(){return {item:factoryRaw,read:()=>factoryCount}}
    export const factoryView=makeFactoryView();
    export const parameterView=makeParameter(factoryRaw);
    export function advanceFactory(){factoryRaw.count++;factoryCount++;conversionCount++;methodState.count++;return factoryView.item===factoryRaw}
    const capturedHidden={count:0};
    export const captured=snapshot({read:()=>capturedHidden.count});
    export function advanceCaptured(){capturedHidden.count++}
    export let count=0;
    export const patternInitial={count:0};export let {patternCount=0,patternState=patternInitial}={};
    export function assignPattern(source){return ({patternCount,patternState}=source)}
    export function loopPattern(){for([patternCount] of [[4],[5]]){};return patternCount}
    export const state={count:0,rows:[{count:0}]};
    export const slot=Symbol('slot');
    export const symbolState={[slot]:{count:0}};
    const hidden={count:0};
    const unrelated=new Map();
    export function read(){return hidden.count}
    export function positive(){return count>0}
    export function rows(){return state.rows}
    export function increment(){count++;state.count++;hidden.count++;state.rows[0].count++}
    export function symbolWrite(){symbolState[slot].count++}
    export function keys(){return Object.keys(state).join(',')}
    export function reflective(){Object.defineProperty(state,'extra',{value:1,enumerable:true,writable:true,configurable:true})}
    export function truncate(){state.rows.length=0}
    export function replaceRows(){state.rows=[{count:10},{count:20}]}
    export function replaceCount(value){return count=value}
    export const importText='import {notAnImport} from "./missing"';
    export function load(){return import('./lazy.ts')}
    export default count;
  `);
  file('lazy.ts', 'export const answer:number=42;');
  symlinkSync('store.ts',join(project,'store-alias.ts'));
  file('barrel.ts', `export {count,state,read,positive,rows,increment,patternCount,patternState as sharedPatternState} from './store';`);
  file('Child.weiv', `<template><p class="child">{{ count }} / {{ read() }}</p><button class="child-action" @click="emit('advance',3)">advance</button><button class="child-callback" @click="props.advanceLocal()">callback</button></template><script lang="ts">import {count,read} from './store-alias.ts';export let props:{advanceLocal:()=>void};</script>`);
  file('App.weiv', `<template>
    <button @click="both">Go</button>
    <p class="main">{{ count }} / {{ read() }} / {{ ns["state"].count }} / {{ local }} / {{ captured }}</p>
    <span class="positive" #if="positive()">positive</span>
    <ul><li #for="row in rows()">{{ row.count }}</li></ul>
    <p class="symbol">{{ symbolState[slot].count }}</p><p class="keys">{{ keys() }}</p>
    <p class="pattern">{{ patternCount }} / {{ patternState.count }}</p>
    <p class="conversion" :title="conversionView">{{ conversionView }}</p>
    <p class="spread-number">{{ spreadNumber() }}</p><p class="spread-json">{{ spreadJson() }}</p>
    <p class="callback-number">{{ callbackNumber() }}</p><p class="callback-json">{{ JSON.stringify({child:callbackJson()}) }}</p>
    <p class="callback-method">{{ callbackMethod() }}</p>
    <p class="parameter">{{ parameterView.item.count }} / {{ parameterView.read() }}</p>
    <p class="factory">{{ factoryView.item.count }} / {{ factoryView.read() }}</p>
    <p class="callable">{{ readSnapshot.read() }}</p><p class="local-callable">{{ localView.read() }}</p>
    <Child @advance="local+=payload" :advanceLocal="()=>local++" />
  </template><script lang="ts">
    import Child from './Child.weiv';
    import captured from './store.ts';
    import {slot,symbolState,keys,captured as readSnapshot,advanceCaptured,factoryView,parameterView,conversionView,spreadNumber,spreadJson,callbackNumber,callbackJson,callbackMethod} from './store.ts';
    import {patternCount,sharedPatternState as patternState} from './barrel';
    import {snapshot} from 'weiv:observable';
    import {count,read,positive,rows,increment} from './barrel';
    import * as ns from './barrel.ts';
    const nativeImplementationDetail=new Map();
    let [local=0]=[]; let localCaptured=0; const localView=snapshot({read:()=>localCaptured});
    function both(){local++;localCaptured++;increment();advanceCaptured()}
  </script>`);
  const result=spawnSync(binary,['--json-diagnostics','emit','app',join(project,'App.weiv'),output],{cwd:root,encoding:'utf8'});
  assert.equal(result.status,0,result.stderr);
  if(result.stderr) assert.equal(JSON.parse(result.stderr).mode,'managed-project');
  assert(JSON.parse(result.stderr).diagnostics.some(item=>item.message.includes('patternState')&&item.message.includes('ownership is unverified')),
    'An opaque incoming parameter must retain its raw-alias boundary warning');
  const modules=readdirSync(join(output,'__weiv_modules'));
  const publishers=modules.filter(name=>name.endsWith('.publisher.mjs'));
  assert.equal(publishers.length,1,'Only the original store needs a publisher; barrels and aliases must share it');
  const storeFile=modules.filter(name=>!name.endsWith('.publisher.mjs')).find(name=>readFileSync(join(output,'__weiv_modules',name),'utf8').includes('export let count'));
  assert(storeFile);
  const store=await import(pathToFileURL(join(output,'__weiv_modules',storeFile)));
  assert.equal((await store.load()).answer,42);
  assert.deepEqual(Object.keys(store),['assignPattern','loopPattern','patternInitial','patternCount','patternState','callbackMethod','callbackNumber','callbackJson','spreadNumber','spreadJson','conversionView','parameterView','advanceFactory','factoryView','advanceCaptured','captured','count','default','importText','increment','load','positive','read','replaceCount','replaceRows','rows','state','slot','symbolState','symbolWrite','keys','reflective','truncate'].sort());
  dom=new JSDOM('<main></main>'); globalThis.window=dom.window; globalThis.document=dom.window.document;
  const app=await import(pathToFileURL(join(output,'bundle.mjs')));
  const target=document.querySelector('main');
  handle=app.mount(target,{});
  assert.equal(target.querySelector('.main').textContent,'0 / 0 / 0 / 0 / 0');
  assert.equal(target.querySelector('.child').textContent,'0 / 0');
  assert.equal(target.querySelector('.positive'),null);
  async function checkPatterns(source){
    const old=source.patternState;assert.equal(old,source.patternInitial);const input={patternCount:2,patternState:{count:3}};
    assert.equal(source.assignPattern(input),input);await tick();
    assert.equal(target.querySelector('.pattern').textContent,'2 / 3');
    assert.notEqual(source.patternState,input.patternState);
    let paints=0;const original=handle.instance.updateDirty;
    handle.instance.updateDirty=(...args)=>{paints++;return original(...args)};
    old.count++;await tick();assert.equal(paints,0);
    source.patternState.count++;await tick();assert.equal(paints,1);
    assert.equal(target.querySelector('.pattern').textContent,'2 / 4');
    assert.throws(()=>source.assignPattern({patternCount:3,get patternState(){throw Error('partial')}}),/partial/);
    await tick();assert.equal(target.querySelector('.pattern').textContent,'3 / 4');
    assert.equal(source.loopPattern(),5);await tick();assert.equal(target.querySelector('.pattern').textContent,'5 / 4');
    handle.instance.updateDirty=original;
  }
  await checkPatterns(store);
  let updates=0;
  const update=handle.instance.updateDirty;
  handle.instance.updateDirty=(...args)=>{updates++;return update(...args)};
  target.querySelector('button').click(); await tick();
  assert.equal(target.querySelector('.main').textContent,'1 / 1 / 1 / 1 / 0');
  assert.equal(target.querySelector('.child').textContent,'1 / 1');
  assert.equal(target.querySelector('.positive').textContent,'positive');
  assert.deepEqual([...target.querySelectorAll('li')].map(node=>node.textContent),['1']);
  assert.equal(updates,1,'Local and multiple shared publishers must merge into one component job');
  assert.equal(target.querySelector('.callable').textContent,'1');assert.equal(target.querySelector('.local-callable').textContent,'1');
  store.increment(); await tick();
  assert.equal(target.querySelector('.main').textContent,'2 / 2 / 2 / 1 / 0');
  assert.equal(target.querySelector('.child').textContent,'2 / 2');
  assert.equal(updates,2);
  store.replaceRows(); await tick();
  assert.deepEqual([...target.querySelectorAll('li')].map(node=>node.textContent),['10','20']);
  store.replaceCount(0); await tick();
  assert.equal(target.querySelector('.positive'),null);
  assert.equal(target.querySelector('.main').textContent,'0 / 2 / 2 / 1 / 0');
  store.advanceCaptured();await tick();assert.equal(target.querySelector('.callable').textContent,'2');
  assert.equal(target.querySelector('.factory').textContent,'0 / 0');
  assert.equal(store.advanceFactory(),true);await tick();
  assert.equal(target.querySelector('.factory').textContent,'1 / 1');
  assert.equal(target.querySelector('.parameter').textContent,'1 / 1');
  assert.equal(target.querySelector('.conversion').textContent,'1');
  assert.equal(target.querySelector('.conversion').getAttribute('title'),'1');
  assert.equal(target.querySelector('.spread-number').textContent,'1');
  assert.equal(target.querySelector('.spread-json').textContent,'{"count":1}');
  assert.equal(target.querySelector('.callback-number').textContent,'1');
  assert.equal(target.querySelector('.callback-method').textContent,'1');
  assert.equal(target.querySelector('.callback-json').textContent,'{"child":{"count":1,"key":"child"}}');
  store.symbolWrite();await tick();assert.equal(target.querySelector('.symbol').textContent,'1');
  store.reflective();await tick();assert.equal(target.querySelector('.keys').textContent,'count,rows,extra');
  const removed=store.state.rows[0];store.truncate();await tick();
  assert.equal(target.querySelectorAll('li').length,0);
  const afterTruncate=updates;removed.count++;await tick();assert.equal(updates,afterTruncate);
  store.replaceRows();await tick();
  target.querySelector('.child-action').click();await tick();assert.equal(target.querySelector('.main').textContent,'0 / 2 / 2 / 4 / 0');
  target.querySelector('.child-callback').click();await tick();assert.equal(target.querySelector('.main').textContent,'0 / 2 / 2 / 5 / 0');
  const beforeDestroy=updates;
  handle.destroy(); store.increment(); await tick();
  assert.equal(updates,beforeDestroy);
  assert.equal(target.textContent,'');
  const entry=join(output,'test-entry.mjs');
  writeFileSync(entry,`export * from './bundle.mjs'; export * as store from './__weiv_modules/${storeFile}';`);
  await build({configFile:false,root:output,logLevel:'silent',build:{target:'esnext',outDir:join(temp,'vite'),minify:false,lib:{entry,formats:['es'],fileName:()=> 'app.mjs'},rollupOptions:{output:{chunkFileNames:'[name]-[hash].mjs'}}}});
  execFileSync('bun',['build',entry,'--target','browser','--format','esm','--outfile',join(temp,'bun-app.mjs')],{cwd:root,stdio:'pipe'});
  for (const bundled of [join(temp,'vite/app.mjs'),join(temp,'bun-app.mjs')]) {
    const module=await import(pathToFileURL(bundled));
    handle=module.mount(target,{});
    assert.equal(target.querySelector('.main').textContent,'0 / 0 / 0 / 0 / 0');
    target.querySelector('button').click();await tick();
    assert.equal(target.querySelector('.main').textContent,'1 / 1 / 1 / 1 / 0');
    assert.equal(target.querySelector('.child').textContent,'1 / 1');
    await checkPatterns(module.store);
    target.querySelector('.child-action').click();await tick();assert.equal(target.querySelector('.main').textContent,'1 / 1 / 1 / 4 / 0');
    target.querySelector('.child-callback').click();await tick();assert.equal(target.querySelector('.main').textContent,'1 / 1 / 1 / 5 / 0');
    assert.equal(target.querySelector('.callable').textContent,'1');assert.equal(target.querySelector('.local-callable').textContent,'1');
    assert.equal(target.querySelector('.factory').textContent,'0 / 0');
    assert.equal(module.store.advanceFactory(),true);await tick();
    assert.equal(target.querySelector('.factory').textContent,'1 / 1');
    assert.equal(target.querySelector('.parameter').textContent,'1 / 1');
    assert.equal(target.querySelector('.conversion').textContent,'1');
    assert.equal(target.querySelector('.conversion').getAttribute('title'),'1');
    assert.equal(target.querySelector('.spread-number').textContent,'1');
    assert.equal(target.querySelector('.spread-json').textContent,'{"count":1}');
    assert.equal(target.querySelector('.callback-number').textContent,'1');
    assert.equal(target.querySelector('.callback-method').textContent,'1');
    assert.equal(target.querySelector('.callback-json').textContent,'{"child":{"count":1,"key":"child"}}');
    module.store.symbolWrite();module.store.reflective();await tick();
    assert.equal(target.querySelector('.symbol').textContent,'1');
    assert.equal(target.querySelector('.keys').textContent,'count,rows,extra');
    module.store.truncate();await tick();assert.equal(target.querySelectorAll('li').length,0);
    assert.equal((await module.store.load()).answer,42);
    handle.destroy();
  }
  console.log('Experimental managed app updates local/shared/private/helper/namespace/structural dependencies with canonical identity');
} finally {
  handle?.destroy(); dom?.window.close();
  globalThis.window=previous.window; globalThis.document=previous.document;
  rmSync(temp,{recursive:true,force:true});
}
