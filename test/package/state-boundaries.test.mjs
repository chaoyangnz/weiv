import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { mkdtempSync, mkdirSync, writeFileSync, rmSync, readFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join, resolve } from "node:path";

const root = resolve(import.meta.dirname, "../..");
const binary = process.env.WEIV_BINARY_PATH || join(root, "zig-out/bin/weiv");
const dir = mkdtempSync(join(tmpdir(), "weiv-boundaries-"));
let serial = 0;
function file(name, source) { writeFileSync(join(dir, name), source); }
function component(template, script) {
  const path = join(dir, `Component${serial++}.weiv`);
  writeFileSync(path, `<template>\n${template}\n</template>\n<script lang="ts">\n${script}\n</script>`);
  return path;
}
function command(...args) {
  const result = spawnSync(binary, args, { cwd: root, encoding: "utf8" });
  assert.equal(result.status, 0, `${args.join(" ")}\n${result.stderr}`);
  return result;
}
function analyze(template, script) {
  const path = component(template, script);
  const report = JSON.parse(command("analyze", "state-boundaries", path).stdout);
  return { path, report, entries: report.diagnostics };
}
try {
  file("raw.ts", 'export const store={count:0}; export const label="fixed"; export function double(value){return value*2}');
  file("barrel.ts", 'export {store as state,label,double} from "./raw";');
  const raw = analyze("<p>{{ state.count }} {{ label }} {{ double(2) }}</p>", 'import {state,label,double} from "./barrel";');
  assert.equal(raw.report.coverage, "initializers-helper-reads-and-assignment-sources");
  assert.equal(raw.entries.length, 1, JSON.stringify(raw.report));
  const warning = raw.entries[0];
  assert.equal(warning.code, "reactivity.untracked_external_state");
  assert.equal(warning.severity, "warning");
  assert.equal(warning.fatal, false);
  assert.equal(warning.sourcePath, raw.path);
  assert.equal(warning.location.line, 2);
  assert.equal(readFileSync(raw.path, "utf8").slice(warning.span.start, warning.span.end), "state.count");
  assert(warning.message.includes("barrel.ts"));
  assert(warning.message.includes("raw.ts"));
  assert(warning.message.includes("observable or subscription adapter"));
  const emitted = command("emit", "js", raw.path);
  assert(emitted.stdout.includes('from "weiv:cells"'));
  assert(emitted.stderr.includes("reactivity.untracked_external_state"));

  file("observed.ts", 'import {observable as track} from "weiv:observable"; export const state=track({count:0});');
  file("observed-barrel.ts", 'export * from "./observed";');
  assert.deepEqual(analyze("<p>{{ state.count }}</p>", 'import {state} from "./observed-barrel";').entries, []);
  for(const script of [
    'let {state}={state:{count:0}};',
    'const [state]=[{count:0}];',
    'import {observable} from "weiv:observable";const source=observable({state:{count:0}});let {state}=source;',
    'import {observable} from "weiv:observable";function make(){return observable({state:{count:0}})}const {state}=make();',
  ])assert.deepEqual(analyze('<p>{{ state.count }}</p>',script).entries,[],script);
  file('raw-destructure.ts','export const source={state:{count:0}};');
  const rawDestructured=analyze('<p>{{ state.count }}</p>','import {source} from "./raw-destructure";let {state}=source;').entries;
  assert(rawDestructured.some(item=>item.message.includes('destructuring source has unverified alias ownership')));
  assert(rawDestructured.some(item=>item.code==='reactivity.untracked_external_state'));
  const customDeclarationIterator=analyze('<p>{{ state.count }}</p>',
    'import {library} from "outside";const input=[{count:0}];input[Symbol.iterator]=function*(){yield library.state};let [state]=input;').entries;
  assert(customDeclarationIterator.some(item=>item.message.includes('array destructuring source is mutated')));
  const inlineInput=analyze('<button @click="state=event.detail.value">replace</button><p>{{ state.count }}</p>','let state={count:0};');
  assert(inlineInput.entries.some(item=>item.message.includes('local or parameter whose ownership is unverified')));
  for(const item of inlineInput.entries){assert.equal(item.sourcePath,inlineInput.path);assert(item.span.end>item.span.start);assert(!item.message.includes('__weiv_templateExpressions'));}
  const inlineLibrary=analyze('<button @click="state=library.getState()">replace</button><p>{{ state.count }}</p>','import {library} from "outside";let state={count:0};').entries;
  assert(inlineLibrary.some(item=>item.message.includes('outside::library')));
  assert.deepEqual(analyze('<button @click="state=Number(event.detail.value)">capture</button><p>{{ state }}</p>','let state=0;').entries,[]);
  file("api.ts", 'export {observable as track,snapshot} from "weiv:observable";');
  file("aliased.ts", 'import {track} from "./api"; export const state=track({count:0});');
  assert.deepEqual(analyze("<p>{{ state.count }}</p>", 'import {state} from "./aliased";').entries, []);
  assert.deepEqual(analyze('<p>{{ state.count }}</p>', 'import * as api from "weiv:observable"; const state=api["observable"]({count:0});').entries,[]);
  const computedNamespace=analyze('<p>{{ ns["store"].count }}</p>', 'import * as ns from "./raw";').entries;
  assert.equal(computedNamespace.length,1);assert.equal(computedNamespace[0].code,'reactivity.untracked_external_state');
  file('dotted.ts','export const a=1; const raw={count:0}; export {raw as "a.b"};');
  assert(analyze('<p>{{ ns["a.b"].count }}</p>', 'import * as ns from "./dotted";').entries.some(d=>d.code==='reactivity.unverified_dependency'));

  file("helper.ts", 'import {store} from "./raw"; export function read(){return store.count}');
  const helper = analyze("<p>{{ read() }}</p>", 'import {read} from "./helper";').entries;
  assert.equal(helper.length, 1);
  assert.equal(helper[0].code, "reactivity.untracked_external_state");
  assert(helper[0].message.includes("helper.ts::read"));
  file("hidden-observable.ts", 'import {state} from "./observed"; export function read(){return state.count}');
  const hidden = analyze("<p>{{ read() }}</p>", 'import {read} from "./hidden-observable";').entries;
  assert.equal(hidden.length, 1);
  assert.equal(hidden[0].code, "reactivity.unverified_dependency");
  assert(hidden[0].message.includes("subscription path"));

  const shadow = analyze("<p>{{ rows.map(store => store.count).join(',') }}</p>", 'import {store} from "./raw"; const rows=[{count:1}];').entries;
  assert.deepEqual(shadow, []);
  for (const expression of ['Math.max(...values)','Number(...values)','JSON.stringify(...values)']) {
    const entries=analyze(`<p>{{ ${expression} }}</p>`,'import {store} from "./raw"; const values=[{valueOf:()=>store.count,toJSON:()=>({count:store.count})}];').entries;
    assert(entries.some(d=>d.code==='reactivity.untracked_external_state'&&d.message.includes('store.count')),JSON.stringify({expression,entries}));
  }
  assert.deepEqual(analyze('<p>{{ Number(...values) }}</p>', 'const cache=new Map();const values=[1,{valueOf:()=>cache.size}];').entries,[]);
  const unknownSpread=analyze('<p>{{ Math.max(...values) }}</p>', 'import {values} from "unavailable-library";').entries;
  assert(unknownSpread.some(d=>d.message.includes('spread argument layout')),JSON.stringify(unknownSpread));
  const mutatedSpread=analyze('<p>{{ Number(...values) }}</p>', 'const values=[1];function change(value){values.unshift(value)}').entries;
  assert(mutatedSpread.some(d=>d.message.includes('spread argument array is mutated')),JSON.stringify(mutatedSpread));
  const shiftedSpread=analyze('<p>{{ Number(...values,view) }}</p>', 'const values=[0];const view={valueOf:()=>1};function change(){const alias=values;alias.pop()}').entries;
  assert(shiftedSpread.some(d=>d.message.includes('spread argument array is mutated')),JSON.stringify(shiftedSpread));
  const spreadReplacer=analyze('<p>{{ JSON.stringify(...values) }}</p>', 'const values=[{count:0},(key,value)=>value];').entries;
  assert(spreadReplacer.some(d=>d.message.includes('JSON replacer effects')),JSON.stringify(spreadReplacer));
  assert.deepEqual(analyze('<p>{{ maximum(values) }}</p>', 'const values=[{valueOf:()=>1}];function maximum(args){return Math.max(...args)}').entries,[]);
  assert.deepEqual(analyze('<p>{{ Math.max(...argumentsFor()) }}</p>', 'const cache=new Map();function argumentsFor(){return [{valueOf:()=>1,unused:()=>cache.size}]}').entries,[]);
  file('spread-hidden.ts', 'import {state} from "./observed";export function argumentsFor(){return [{valueOf:()=>state.count}]}');
  const hiddenSpread=analyze('<p>{{ Math.max(...argumentsFor()) }}</p>', 'import {argumentsFor} from "./spread-hidden";').entries;
  assert(hiddenSpread.some(d=>d.message.includes('subscription path')),JSON.stringify(hiddenSpread));
  const recursiveSpread=analyze('<p>{{ Math.max(...argumentsFor()) }}</p>', 'function argumentsFor(){return argumentsFor()}').entries;
  assert(recursiveSpread.some(d=>d.message.includes('spread argument layout')),JSON.stringify(recursiveSpread));
  const ambiguousSpread=analyze('<p>{{ Math.max(...argumentsFor()) }}</p>', 'let condition=true;function argumentsFor(){if(condition)return [1];return [2,3]}').entries;
  assert(ambiguousSpread.some(d=>d.message.includes('spread argument layout')),JSON.stringify(ambiguousSpread));
  for (const [expression,script] of [
    ['invoke(()=>count)','let count=0;function invoke(callback){return callback()}'],
    ['invoke(value=>value.count,raw)','const raw={count:0};function invoke(callback,value){return callback(value)}'],
    ['invoke(make)','let count=0;const cache=new Map();function make(){return {toString:()=>String(count),unused:()=>cache.size}}function invoke(callback){return callback()}'],
  ]) assert.deepEqual(analyze(`<p>{{ ${expression} }}</p>`,script).entries,[],expression);
  file('invoke.ts', 'export function invoke(callback,value){return callback(value)}');
  assert.deepEqual(analyze('<p>{{ invoke(()=>count) }}</p>', 'import {invoke} from "./invoke";let count=0;').entries,[]);
  const unknownCallback=analyze('<p>{{ invoke(callback) }}</p>', 'import {callback} from "unavailable-library";function invoke(callback){return callback()}').entries;
  assert(unknownCallback.length>0,JSON.stringify(unknownCallback));
  const reassignedCallback=analyze('<p>{{ invoke(callback) }}</p>', 'let callback=()=>1;function change(next){callback=next}function invoke(callback){return callback()}').entries;
  assert(reassignedCallback.some(d=>d.message.includes('reassigned callback')),JSON.stringify(reassignedCallback));
  const mutatingCallback=analyze('<p>{{ invoke(()=>{raw.count++;return raw.count}) }}</p>', 'const raw={count:0};function invoke(callback){return callback()}').entries;
  assert(mutatingCallback.some(d=>d.message.includes('mutations')),JSON.stringify(mutatingCallback));
  const recursiveCallback=analyze('<p>{{ invoke(invoke) }}</p>', 'function invoke(callback){return callback(callback)}').entries;
  assert(recursiveCallback.some(d=>d.message.includes('callback invocation')&&d.message.includes('recursive cycle')),JSON.stringify(recursiveCallback));
  const repeatedCallback=analyze('<p>{{ invoke(make) + String(make) }}</p>', 'let count=0;function make(){return count}function invoke(callback){return callback()}').entries;
  assert(repeatedCallback.some(d=>d.message.includes('callable conversion properties')),JSON.stringify(repeatedCallback));
  const directObservableCallback=analyze('<p>{{ invoke(value=>value.count,state) }}</p>', 'import {invoke} from "./invoke";import {state} from "./observed";').entries;
  assert.deepEqual(directObservableCallback,[]);
  file('private-callback.ts', 'import {state} from "./observed";export function read(){return state.count}');
  const privateCallback=analyze('<p>{{ invoke(read) }}</p>', 'import {read} from "./private-callback";function invoke(callback){return callback()}').entries;
  assert(privateCallback.some(d=>d.message.includes('subscription path')),JSON.stringify(privateCallback));
  const lexicalReceiver=analyze('<p>{{ view.read() }}</p>', 'const view={count:0,read:()=>String(this?.count??0)};').entries;
  assert(lexicalReceiver.some(d=>d.message.includes('this')||d.message.includes('receiver')),JSON.stringify(lexicalReceiver));
  for (const [expression,script] of [
    ['invoke(holder)','const holder={count:0,read(){return this.count}};function invoke(value){return value.read()}'],
    ['invoke(holder,"read")','const cache=new Map();const holder={count:0,read(){return this.count},unused:()=>cache.size};function invoke(value,key){return value[key]()}'],
  ]) assert.deepEqual(analyze(`<p>{{ ${expression} }}</p>`,script).entries,[],expression);
  const extractedMethod=analyze('<p>{{ invoke(holder) }}</p>', 'const holder={count:0,read(){return this.count}};function invoke(value){const read=value.read;return read()}').entries;
  assert(extractedMethod.some(d=>d.message.includes('this')||d.message.includes('receiver')),JSON.stringify(extractedMethod));
  const varyingMethod=analyze('<p>{{ invoke(holder,key) }}</p>', 'const holder={read:()=>1,other:()=>2};let key="read";function change(){key="other"}function invoke(value,key){return value[key]()}').entries;
  assert(varyingMethod.some(d=>d.message.includes('computed callable key')),JSON.stringify(varyingMethod));
  const nativeReceiver=analyze('<p>{{ invoke(rows) }}</p>', 'const rows=[1];function invoke(value){return value.map(item=>item)}').entries;
  assert(nativeReceiver.some(d=>d.message.includes('callable invocation effects')),JSON.stringify(nativeReceiver));
  for (const [expression,script] of [
    ['Math.max(...invoke(()=>[count]))','let count=0;function invoke(callback){return callback()}'],
    ['Math.max(...invoke(holder,"read"))','const holder={count:0,read(){return [{valueOf:()=>this.count}]}};function invoke(value,key){return value[key]()}'],
  ]) assert.deepEqual(analyze(`<p>{{ ${expression} }}</p>`,script).entries,[],expression);
  const ambiguousCallbackArray=analyze('<p>{{ Math.max(...invoke(callback)) }}</p>', 'let condition=true;function callback(){if(condition)return [1];return [2,3]}function invoke(callback){return callback()}').entries;
  assert(ambiguousCallbackArray.some(d=>d.message.includes('spread')&&d.message.includes('layout')),JSON.stringify(ambiguousCallbackArray));
  const loop = analyze('<div #for="store in rows"><p>{{ store.count }}</p></div>', 'import {store} from "./raw"; const rows=[{count:1}];').entries;
  assert.deepEqual(loop, []);
  for (const template of [
    '<p>{{ rows.map(row=>row.callback.count).join() }}</p>',
    '<p>{{ rows.map(function(row){return row.callback.count}).join() }}</p>',
    '<div #for="row in rows"><p>{{ row.callback.count }}</p></div>',
  ]) {
    const entries=analyze(template, 'import {snapshot} from "weiv:observable"; const callback=Object.assign(()=>0,{count:0}); const rows=snapshot([{callback}]);').entries;
    assert(entries.some(d=>d.message.includes('callable properties')),JSON.stringify({template,entries}));
  }
  assert.deepEqual(analyze('<div #for="row in rows"><p>{{ row.count }}</p></div>', 'import {snapshot} from "weiv:observable"; const rows=snapshot([{count:0}]);').entries,[]);
  const unused = analyze('<button @click="read">Go</button><p>{{ count }}</p>', 'import {read} from "./helper"; let count=0;').entries;
  assert.deepEqual(unused, []);

  for (const script of [
    'const callback=Object.assign(()=>0,{count:0}); const rows={map(){return callback}};',
    'const callback=Object.assign(()=>0,{count:0}); const rows=[]; rows.map=()=>callback;',
  ]) {
    const entries=analyze('<p>{{ rows.map().length }}</p>',script).entries;
    assert(entries.some(d=>d.message.includes('return-value projection')),JSON.stringify(entries));
  }
  const projectedResult=analyze('<p>{{ get().callback.count }}</p>', 'const callback=Object.assign(()=>0,{count:0}); function get(){return {callback}}').entries;
  assert(projectedResult.some(d=>d.message.includes('return-value projection')&&d.message.includes('get().callback')),JSON.stringify(projectedResult));
  const projectedHelper=analyze('<p>{{ read() }}</p>', 'const callback=Object.assign(()=>0,{count:0}); function get(){return {callback}} function read(){return get().callback.count}').entries;
  assert(projectedHelper.some(d=>d.message.includes('return-value projection')),JSON.stringify(projectedHelper));
  const nestedLoop=analyze('<div #for="group in groups"><div #for="row in group.rows"><p>{{ row.callback.count }}</p></div></div>', 'import {snapshot} from "weiv:observable"; const callback=Object.assign(()=>0,{count:0}); const groups=snapshot([{rows:[{callback}]}]);').entries;
  assert(nestedLoop.some(d=>d.message.includes('callable properties')),JSON.stringify(nestedLoop));
  const retainedScalar=analyze('<p>{{ store.read() }}</p>', 'function makeStore(){let count=0;return {read:()=>count,increment(){count++}}} const store=makeStore();').entries;
  assert(retainedScalar.some(d=>d.message.includes('retain raw local state')),JSON.stringify(retainedScalar));
  assert.deepEqual(analyze('<p>{{ state.count }}</p>', 'import {observable} from "weiv:observable"; import {use} from "outside"; const state=observable({count:0}); function update(){use(state)}').entries,[]);
  const retained = analyze('<p>{{ store.item.count }}</p>', 'function makeStore(){const item={count:0};return {item,increment(){item.count++}}} const store=makeStore();').entries;
  assert(retained.some(d=>d.message.includes('retain raw local state')),JSON.stringify(retained));
  assert.deepEqual(analyze('<p>{{ calculate() }}</p>', 'function calculate(){let total=0;for(let i=0;i<3;i++) total+=i;return total}').entries,[]);
  assert.deepEqual(analyze('<p>{{ store.item.count }}</p>', 'import {observable} from "weiv:observable"; function makeStore(){const item=observable({count:0});return {item,increment(){item.count++}}} const store=makeStore();').entries,[]);
  for (const body of [
    'const assign=Object.assign; function replace(){assign(state,library.getState())}',
    'function forward(target,next){Object.assign(target,next)} function replace(){forward(state,library.getState())}',
  ]) {
    const entries=analyze('<p>{{ state.count }}</p>', 'import {library} from "outside"; const state={count:0}; '+body).entries;
    assert(entries.some(d=>d.message.includes('incoming mutations and retained aliases')),JSON.stringify(entries));
  }
  assert.deepEqual(analyze('<p>{{ state.count }}</p>', 'const state={count:0}; function read(value){return value.count} function use(){return read(state)}').entries,[]);

  for (const operation of [
    'Reflect.apply(Object.assign,null,[state,library.getState()])',
    'Object.assign.call(null,state,library.getState())',
    'Object.assign.apply(null,[state,library.getState()])',
    'Object.assign(...[state,library.getState()])',
    'const args=[state,library.getState()]; Reflect.apply(Object.assign,null,args)',
    'let args=[]; args=[state,library.getState()]; Object.assign(...args)',
    'const holder={destination:state}; Object.assign(holder.destination,library.getState())',
    'const holder={destination:state}; const {destination}=holder; Object.assign(destination,library.getState())',
    'const alias=state; Object.assign(alias,library.getState())',
    'const forward=Object.assign.bind(null,state); forward(library.getState())',
    'const consume=()=>Reflect.apply(Object.assign,null,args); const args=[state,library.getState()]; consume()',
  ]) {
    const entries=analyze('<p>{{ state.count }}</p>', 'import {library} from "outside"; const state={count:0}; function update(){'+operation+'}').entries;
    assert(entries.some(d=>d.message.includes('incoming mutations and retained aliases')),JSON.stringify({operation,entries}));
  }
  // Lexical shadowing and scalar computations do not pass the selected object.
  assert.deepEqual(analyze('<p>{{ state.count }}</p>', 'const state={count:0}; function update(state){Reflect.apply(Object.assign,null,[state,{count:1}])}').entries,[]);
  assert.deepEqual(analyze('<p>{{ state.count }}</p>', 'const state={count:0}; function update(){Reflect.apply(console.log,null,[state.count+1])}').entries,[]);
  assert.deepEqual(analyze('<p>{{ state.count }}</p>', 'const state={count:0}; function update(){Object.keys({state})}').entries,[]);
  assert.deepEqual(analyze('<p>{{ state.count }}</p>', 'const state={count:0}; function update(){Object.assign({}, {child:state})}').entries,[]);
  for (const script of [
    'function create(){return {count:0}} function make(){const item=create();return {item,increment(){item.count++}}} const store=make();',
    'function make(){const read=()=>count;let count;count=0;return {read,increment(){count++}}} const store=make();',
    'function make(){class Item{count=0};const item=new Item();return {item,increment(){item.count++}}} const store=make();',
  ]) {
    const entries=analyze('<p>{{ store.item?.count }} {{ store.read?.() }}</p>',script).entries;
    assert(entries.some(d=>d.message.includes('retain raw local state')||d.message.includes('local call result whose ownership is unverified')),JSON.stringify({script,entries}));
  }
  assert.deepEqual(analyze('<p>{{ store.read() }}</p>', 'function make(){const count=Number(2);return {read:()=>count}} const store=make();').entries,[]);
  assert.deepEqual(analyze('<p>{{ store.item.count }}</p>', 'import {track} from "./api"; function make(){const item=track({count:0});return {item,increment(){item.count++}}} const store=make();').entries,[]);
  for (const body of [
    'const alias=state; alias.child=library.getState()',
    'const holder={target:state}; holder.target.child=library.getState()',
    'const alias=state; alias[key]=library.getState()',
    'const holder={target:state}; const {target:alias}=holder; alias.child=library.getState()',
  ]) {
    const entries=analyze('<p>{{ state.child.count }}</p>','import {library} from "outside"; const state={child:{count:0}}; function update(key){'+body+'}').entries;
    assert(entries.some(d=>d.message.includes('incoming')&&d.message.includes('outside::library')),JSON.stringify({body,entries}));
  }
  assert.deepEqual(analyze('<p>{{ state.child.count }}</p>','import {library} from "outside"; const state={child:{count:0}}; function update(){let alias=state;alias=library.getState()}').entries,[]);
  for (const operation of [
    '({child:alias.child}=library.getState())',
    '[alias.child]=library.getState()',
    '({nested:{child:alias.child}}=library.getState())',
    'for(alias.child of library.getState()){}',
    'for([alias.child] of library.getState()){}',
    '(alias.child as any)=library.getState()',
    '({child:alias.child=library.getState()}=observable({}))',
    '[alias.child=library.getState()]=observable([])',
  ]) {
    const entries=analyze('<p>{{ state.child.count }}</p>', 'import {observable} from "weiv:observable"; import {library} from "outside"; const state={child:{count:0}}; function update(){const alias=state;'+operation+'}').entries;
    assert(entries.some(d=>d.message.includes('incoming')&&d.message.includes('outside::library')),JSON.stringify({operation,entries}));
  }
  assert.deepEqual(analyze('<p>{{ state.child }}</p>', 'import {library} from "outside"; const state={child:""}; function update(){const alias=state;for(alias.child in library){}}').entries,[]);
  for(const declaration of ['async function make(){return {count:1}}','function* make(){return {count:1}}']) {
    const entries=analyze('<p>{{ view.count }}</p>',declaration+' const view=make();').entries;
    assert(entries.some(d=>d.message.includes('Promise or iterator')),JSON.stringify(entries));
  }
  assert.deepEqual(analyze('<p>{{ view.count }}</p>','function make(){const parent={child:{count:1}};return parent.child} const view=make();').entries,[]);
  const replacedReturn=analyze('<p>{{ view.count }}</p>','function make(){let item={count:0};item={count:1};return item} const view=make();').entries;
  assert(replacedReturn.some(d=>d.message.includes('return-value provenance is unresolved')),JSON.stringify(replacedReturn));
  assert.deepEqual(analyze('<p>{{ view.read() }}</p>','import {snapshot} from "weiv:observable"; function make(){const captured=snapshot({count:2});return {read:()=>captured.count}} const view=make();').entries,[]);
  for (const declaration of ['export default function make()','export default function()']) {
    file('returned-default.ts','import {snapshot} from "weiv:observable"; const callback=Object.assign(()=>0,{count:0}); '+declaration+'{const captured=snapshot({callback});return captured}');
    const entries=analyze('<p>{{ view.callback.count }}</p>','import make from "./returned-default"; const view=make();').entries;
    assert(entries.some(d=>d.message.includes('callable properties')&&d.message.includes('returned-default.ts')),JSON.stringify(entries));
  }
  const returnedSnapshot=analyze('<p>{{ view.callback.count }}</p>','import {snapshot} from "weiv:observable"; const callback=Object.assign(()=>0,{count:0}); function make(){const captured=snapshot({callback});return captured} const view=make();').entries;
  assert(returnedSnapshot.some(d=>d.message.includes('callable properties')),JSON.stringify(returnedSnapshot));
  const returnedClosure=analyze('<p>{{ view.read() }}</p>','import {observable} from "weiv:observable"; function make(){const item=observable({count:0});return {read:()=>item.count}} const view=make();').entries;
  assert(returnedClosure.some(d=>d.message.includes('helper-local values without a verified subscription path')),JSON.stringify(returnedClosure));
  const forwardedParam=analyze('<p>{{ view.count }}</p>','function identity(value){return value} const view=identity({count:0});').entries;
  assert.deepEqual(forwardedParam,[]);
  assert.deepEqual(analyze('<p>{{ view.count }}</p>','import {library} from "outside"; function make(){return {count:1,unused:()=>library.count}} const view=make();').entries,[]);
  assert.deepEqual(analyze('<p>{{ view.child.count }}</p>','function make(){const item={count:1};return {child:item}} const view=make();').entries,[]);
  const returnedEffect=analyze('<p>{{ view.count }}</p>','import {library} from "outside"; function make(){const item={count:0};library.retain(item);return item} const view=make();').entries;
  assert(returnedEffect.some(d=>d.message.includes('outside::library')),JSON.stringify(returnedEffect));
  for (const script of [
    'function identity(value){return value} const raw={count:0}; const view=identity(raw);',
    'function identity(value){return value} function forward(input){return identity(input)} const view=forward({count:0});',
    'function identity(value={count:0}){return value} const view=identity();',
    'function identity(first,second=first){return second} const view=identity({count:0});',
    'function identity(value={count:0}){return value} const view=identity(undefined);',
  ]) {
    assert.deepEqual(analyze('<p>{{ view.count }}</p>',script).entries,[],script);
  }
  const returnedParameterCallable=analyze('<p>{{ view.callback.count }}</p>','const callback=Object.assign(()=>0,{count:0}); function identity(value){return value} const view=identity({callback});').entries;
  assert(returnedParameterCallable.some(d=>d.message.includes('callable properties')),JSON.stringify(returnedParameterCallable));
  const spreadParameter=analyze('<p>{{ view.count }}</p>','function identity(value){return value} const inputs=[{count:0}]; const view=identity(...inputs);').entries;
  assert(spreadParameter.some(d=>d.message.includes('return-value provenance is unresolved')),JSON.stringify(spreadParameter));
  assert.deepEqual(analyze('<p>{{ view.read() }}</p>','const raw={count:0}; function make(value){return {read:()=>value.count}} const view=make(raw);').entries,[]);
  const replacedCapture=analyze('<p>{{ view.read() }}</p>','let raw={count:0}; function make(value){return {read:()=>value.count}} const view=make(raw); function replace(){raw={count:1}}').entries;
  assert(replacedCapture.some(d=>d.message.includes('verified subscription path')),JSON.stringify(replacedCapture));
  for(const script of [
    'function make({item}){return item} const view=make({item:{count:1}});',
    'function make([item]){return item} const view=make([{count:1}]);',
    'function make(source){const {item}=source;return item} const view=make({item:{count:1}});',
    'function make(...items){return items[0]} const view=make({count:1});',
    'function make(){const {count}= {count:1};return {read:()=>count}} const view=make();',
  ]) {
    const template=script.includes('read:')?'<p>{{ view.read() }}</p>':'<p>{{ view.count }}</p>';
    assert.deepEqual(analyze(template,script).entries,[],script);
  }
  const destructuredCallback=analyze('<p>{{ view.callback.count }}</p>','const callback=Object.assign(()=>0,{count:0});function make({item}){return item}const view=make({item:{callback}});').entries;
  assert(destructuredCallback.some(d=>d.message.includes('callable properties')),JSON.stringify(destructuredCallback));
  for(const template of ['<p>{{ view }}</p>','<p>{{ String(view) }}</p>','<p>{{ `${view}` }}</p>','<p :title="view">text</p>']) {
    const entries=analyze(template,'import {library} from "outside"; const view={toString:()=>library.count};').entries;
    assert(entries.some(d=>d.message.includes('outside::library')&&d.message.includes('implicit toString')),JSON.stringify({template,entries}));
  }
  for(const template of ['<p>{{ view + 1 }}</p>','<p>{{ Number(view) }}</p>','<p>{{ -view }}</p>']) {
    const entries=analyze(template,'import {library} from "outside"; const view={valueOf:()=>library.count};').entries;
    assert(entries.some(d=>d.message.includes('outside::library')&&d.message.includes('implicit valueOf')),JSON.stringify({template,entries}));
  }
  assert.deepEqual(analyze('<p>{{ view === view }}</p><p #if="view">yes</p>','import {library} from "outside"; const view={toString:()=>library.count};').entries,[]);
  const joinedHooks=analyze('<p>{{ rows.join() }}</p>','import {snapshot} from "weiv:observable";import {library} from "outside";const rows=snapshot([{toString:()=>library.count}]);').entries;
  assert(joinedHooks.some(d=>d.message.includes('outside::library')&&d.message.includes('implicit toString')),JSON.stringify(joinedHooks));
  const methodProperties=analyze('<p>{{ rows.map.count }}</p>','import {snapshot} from "weiv:observable";const rows=snapshot([]);').entries;
  assert(methodProperties.some(d=>d.message.includes('native array methods')),JSON.stringify(methodProperties));
  for(const wrapper of ['{callback}','snapshot({callback})','observable({callback})']) {
    const entries=analyze('<p>{{ view.read() }}</p>','import {snapshot,observable} from "weiv:observable";const callback=Object.assign(()=>0,{count:0});const raw='+wrapper+';function make(value){return {read:()=>value.callback.count}}const view=make(raw);').entries;
    assert(entries.some(d=>d.message.includes('verified subscription path')||d.message.includes('callable properties')),JSON.stringify({wrapper,entries}));
  }
  assert.deepEqual(analyze('<p>{{ String(view) }}</p>','import {library} from "outside"; const view={toString:()=>String(1),valueOf:()=>library.count};').entries,[]);
  assert.deepEqual(analyze('<p>{{ Number(view) }}</p>','import {library} from "outside"; const view={toString:()=>library.count,valueOf:()=>Number(1)};').entries,[]);
  const inheritedHook=analyze('<p>{{ view }}</p>','let count=0; const view={__proto__:{toString:()=>count}};').entries;
  assert(inheritedHook.some(d=>d.message.includes('prototype conversion hooks')),JSON.stringify(inheritedHook));
  file('parameter-factory.ts','export function identity(value){return value}');
  file('parameter-barrel.ts','export * as tools from "./parameter-factory";');
  for(const script of [
    'import * as api from "./parameter-factory";const view=api.identity({count:1});',
    'import {tools} from "./parameter-barrel";const view=tools.identity({count:1});',
    'import * as api from "./parameter-factory";const alias=api;const view=alias.identity({count:1});',
  ]) assert.deepEqual(analyze('<p>{{ view.count }}</p>',script).entries,[],script);
  const unknownMethod=analyze('<p>{{ view.callback.count }}</p>','const callback=()=>0;callback.count=0;const api={identity(value){return value}};const view=api.identity({callback});').entries;
  assert(unknownMethod.some(d=>d.message.includes('unverified return-value provenance')),JSON.stringify(unknownMethod));
  const wrappedUndefinedDefault=analyze('<p>{{ view.callback.count }}</p>','import {snapshot} from "weiv:observable";const callback=()=>0;callback.count=0;const input=snapshot(undefined);function make(value={callback}){return value}const view=make(input);').entries;
  assert(wrappedUndefinedDefault.some(d=>d.message.includes('callable properties')),JSON.stringify(wrappedUndefinedDefault));
  assert.deepEqual(analyze('<p>{{ view.count }}</p>','import {snapshot} from "weiv:observable";import {library} from "outside";const input=snapshot({count:1});function make(value=library.getState()){return value}const view=make(input);').entries,[]);
  for(const [initializer,path] of [['[]','value.map.count'],['{}','value.toString.count'],['{count:0}','value[key]']]) {
    const entries=analyze('<p>{{ view.read() }}</p>','const raw='+initializer+';const key="count";function make(value){return {read:()=>'+path+'}}const view=make(raw);').entries;
    assert(entries.some(d=>d.message.includes('captured path may address untracked callable properties')),JSON.stringify({path,entries}));
  }
  assert.deepEqual(analyze('<p>{{ view.read() }}</p>','const raw={values:{count:0}};function make(value){return {read:()=>value.values.count}}const view=make(raw);').entries,[]);
  for(const expression of ['view || "empty"','view ?? "empty"','true ? view : "empty"','null ?? view','(0,view)']) {
    const entries=analyze('<p>{{ '+expression+' }}</p>','import {library} from "outside";const view={toString:()=>library.count};').entries;
    assert(entries.some(d=>d.message.includes('implicit toString')),JSON.stringify({expression,entries}));
  }
  for(const expression of ['view && "ready"','false ? view : "ready"','true || view','false && view']) {
    assert.deepEqual(analyze('<p>{{ '+expression+' }}</p>','import {library} from "outside";const view={toString:()=>library.count};').entries,[],expression);
  }
  assert.deepEqual(analyze('<p>{{ String(view) }}</p>','import {library} from "outside";function String(value){return "fixed"}const view={toString:()=>library.count};').entries,[]);
  const deepResult=analyze('<p>{{ '+('false || ('.repeat(40))+'view'+(')'.repeat(40))+' }}</p>','let count=0;const view={toString:()=>count};').entries;
  assert(deepResult.some(d=>d.message.includes('analysis limit')||d.message.includes('conversion provenance is unresolved')),JSON.stringify(deepResult));
  const localeHook=analyze('<p>{{ rows.toLocaleString() }}</p>','import {library} from "outside";const rows=[{toString:()=>"fixed",toLocaleString:()=>library.count}];').entries;
  assert(localeHook.some(d=>d.message.includes('implicit toLocaleString')&&d.message.includes('outside::library')),JSON.stringify(localeHook));
  const jsonSource=analyze('<p>{{ JSON.stringify(view) }}</p>','import {library} from "outside";const view={toJSON:()=>({count:library.count})};').entries;
  assert(jsonSource.some(d=>d.message.includes('implicit toJSON')&&d.message.includes('outside::library')),JSON.stringify(jsonSource));
  assert.deepEqual(analyze('<p>{{ JSON.stringify(view) }}</p>','import {library} from "outside";const view={toJSON:()=>({count:1}),unused:{toJSON:()=>library.count}};').entries,[]);
  assert.deepEqual(analyze('<p>{{ JSON.stringify({count:1,unused:()=>library.count}) }}</p>','import {library} from "outside";').entries,[]);
  assert.deepEqual(analyze('<p>{{ JSON.stringify(view,null,2) }}</p>','const view={count:1,toJSON(){return {count:this.count}}};').entries,[]);
  const jsonReplacer=analyze('<p>{{ JSON.stringify(view,replace) }}</p>','const view={count:1};const replace=(key,value)=>value;').entries;
  assert(jsonReplacer.some(d=>d.message.includes('JSON replacer effects')),JSON.stringify(jsonReplacer));
  const convertedHelper=analyze('<p>{{ String(get()) }}</p>','import {library} from "outside";function get(){return {toString:()=>library.count}}').entries;
  assert(convertedHelper.some(d=>d.message.includes('implicit toString')&&d.message.includes('outside::library')),JSON.stringify(convertedHelper));
  assert.deepEqual(analyze('<p>{{ get() }}</p>','import {library} from "outside";function get(){return {toString:()=>String(1),unused:()=>library.count}}').entries,[]);
  const functionJson=analyze('<p>{{ JSON.stringify(fn) }}</p>','let count=0;const fn=()=>0;fn.toJSON=()=>count;').entries;
  assert(functionJson.some(d=>d.message.includes('callable serialization properties')),JSON.stringify(functionJson));
  const incoming = analyze('<p>{{ state.count }}</p>', 'import {library} from "outside"; let state={count:0}; function replace(){state=library.getState()}').entries;
  assert(incoming.some(d => d.message.includes("incoming") && d.message.includes("outside::library")));
  const parameter = analyze('<p>{{ state.count }}</p>', 'let state={count:0}; function replace(next){state=next}').entries;
  assert(parameter.some(d => d.message.includes("local or parameter")));
  const memberInput = analyze('<p>{{ state.child.count }}</p>', 'let state={child:{count:0}}; function replace(next){state.child=next}').entries;
  assert(memberInput.some(d => d.message.includes("incoming.child")));
  const computed=analyze('<p>{{ state.child }}</p>', 'let state={}; function replace(key,next){state[key].child=next}').entries;
  assert(computed.some(d=>d.message.includes('incoming.[computed].child')&&d.message.includes('local or parameter')));
  const defaults=analyze('<p>{{ state.child }}</p>', 'import {observable} from "weiv:observable"; import {library} from "outside"; let state={}; function replace(){({child:state.child=library.getState()}=observable({}))}').entries;
  assert(defaults.some(d=>d.message.includes('incoming(default).child')&&d.message.includes('outside::library')));
  const iteration=analyze('<p>{{ state.child }}</p>', 'let state={}; function replace(rows){for(state.child of rows){}}').entries;
  assert(iteration.some(d=>d.message.includes('incoming(for-of).child')&&d.message.includes('local or parameter')));
  assert.deepEqual(analyze('<p>{{ state }}</p>', 'import {library} from "outside"; let state=""; function keys(){for(state in library){}}').entries,[]);
  assert.deepEqual(analyze('<p>{{ state.child }}</p>', 'import {library} from "outside"; let state={}; function shadow(state){({x:state.child=library.getState()}={})}').entries,[]);
  assert(!analyze('<p>{{ read() }}</p>', 'let read=()=>0; function replace(){read=()=>1}').entries.some(d=>d.message.includes('reassigned function binding')));
  assert(analyze('<p>{{ read() }}</p>', 'function read(){return 0} function replace(){read=()=>1}').entries.some(d=>d.message.includes('reassigned function binding')));
  for(const operation of [
    'state.items.push(library.getState())',
    'state.items.splice(0,0,...library.getState())',
    'Object.assign(state,library.getState())',
    'Object.defineProperty(state,"child",{value:library.getState(),writable:true})',
    'Object.defineProperties(state,{child:{value:library.getState(),writable:true}})',
    'Reflect.set(state,"child",library.getState())',
  ]){
    const entries=analyze('<p>{{ state.items.length }}</p>', `import {library} from "outside"; let state={items:[]}; function insert(){${operation}}`).entries;
    assert(entries.some(d=>d.message.includes('outside::library')&&d.message.includes('incoming(')),operation);
  }
  for(const operation of ['state.items.push(observable(next))','Object.assign(state,observable(next))','Object.defineProperty(state,"child",{value:observable(next),writable:true})']){
    assert.deepEqual(analyze('<p>{{ state.items.length }}</p>',`import {observable} from "weiv:observable"; let state={items:[]}; function insert(next){${operation}}`).entries,[],operation);
  }
  assert.deepEqual(analyze('<p>{{ state.count }}</p>', 'let state={count:0}; function replace(state){state={count:1}}').entries, []);
  assert.deepEqual(analyze('<p>{{ state.count }}</p>', 'let state={count:0}; function replace(){state={count:1}}').entries, []);
  assert.deepEqual(analyze('<p>{{ state.count }}</p>', 'import {observable} from "weiv:observable"; let state={count:0}; function replace(next){state=observable(next)}').entries, []);
  assert.deepEqual(analyze('<p>{{ state }}</p>', 'let state=0; function clear(){state=undefined;state=NaN;state=Infinity;state=String(1)}').entries, []);
  assert(analyze('<p>{{ state }}</p>', 'let state={}; function replace(){state=this}').entries.some(d=>d.message.includes('global::this')));

  const namespace = analyze("<p>{{ ns.label }} {{ ns.store.count }}</p>", 'import * as ns from "./raw";').entries;
  assert.equal(namespace.length, 1);
  assert.equal(namespace[0].code, "reactivity.untracked_external_state");
  const indirect = analyze("<p>{{ ns.state.count }}</p>", 'import * as ns from "./observed";').entries;
  assert.equal(indirect.length, 1);
  assert(indirect[0].message.includes("subscription path"));

  file("cycle-a.ts", 'export * from "./cycle-b";');
  file("cycle-b.ts", 'export * from "./cycle-a";');
  assert.equal(analyze("<p>{{ state.count }}</p>", 'import {state} from "./cycle-a";').entries[0].code, "reactivity.unverified_dependency");
  file("one.ts", "export const value=1;");
  file("two.ts", "export const value=2;");
  file("ambiguous.ts", 'export * from "./one"; export * from "./two";');
  assert(analyze("<p>{{ value }}</p>", 'import {value} from "./ambiguous";').entries[0].message.includes("ambiguous"));

  file("diamond-left.ts", 'export {state} from "./observed";');
  file("diamond-right.ts", 'export {state} from "./observed";');
  file("diamond.ts", 'export * from "./diamond-left"; export * from "./diamond-right";');
  assert.deepEqual(analyze("<p>{{ state.count }}</p>", 'import {state} from "./diamond";').entries, []);
  file("unknown-star.ts", 'export * from "./observed"; export * from "opaque-package";');
  assert.equal(analyze("<p>{{ state.count }}</p>", 'import {state} from "./unknown-star";').entries[0].code, "reactivity.unverified_dependency");
  file("api-namespace.ts", 'export * as api from "weiv:observable";');
  file("namespaced-factory.ts", 'import {api} from "./api-namespace"; export const state=api.observable({count:0});');
  assert.deepEqual(analyze("<p>{{ state.count }}</p>", 'import {state} from "./namespaced-factory";').entries, []);
  file("factory-left.ts", 'export {observable as make} from "weiv:observable";');
  file("factory-right.ts", 'export function make(value){return value}');
  file("factory-conflict.ts", 'export * from "./factory-left"; export * from "./factory-right";');
  file("conflict-user.ts", 'import {make} from "./factory-conflict"; export const state=make({count:0});');
  assert.equal(analyze("<p>{{ state.count }}</p>", 'import {state} from "./conflict-user";').entries[0].code, "reactivity.unverified_dependency");
  file("changed.ts", 'import {observable} from "weiv:observable"; export let state=observable({count:0}); export function replace(){state={count:1}}');
  assert.equal(analyze("<p>{{ state.count }}</p>", 'import {state} from "./changed";').entries[0].code, "reactivity.untracked_external_state");
  const structured = JSON.parse(command("--json-diagnostics", "emit", "js", raw.path).stderr);
  assert.equal(structured.diagnostics[0].code, "reactivity.untracked_external_state");

  file("captured.ts", 'import {observable,snapshot} from "weiv:observable"; const source=observable({nested:{count:1}}); export const captured=snapshot(source);');
  assert.deepEqual(analyze("<p>{{ captured.nested.count }}</p>", 'import {captured} from "./captured";').entries, []);
  const snapshotProperties=analyze('<p>{{ captured.callback.count }}</p>', 'import {snapshot} from "weiv:observable"; const callback=Object.assign(()=>0,{count:0}); const captured=snapshot({callback});').entries;
  assert(snapshotProperties.some(d=>d.message.includes('callable properties')));
  assert(analyze('<p>{{ captured.callback.count }}</p>', 'import {snapshot} from "weiv:observable"; const callback=()=>0; let captured=snapshot({callback}); function recapture(){captured=snapshot({callback})}').entries.some(d=>d.message.includes('callable properties')));
  assert(analyze('<p>{{ captured.callback() }}</p>', 'import {snapshot} from "weiv:observable"; import {library} from "outside"; let captured=snapshot({callback:()=>0}); function recapture(){captured=snapshot({callback:library.read})}').entries.some(d=>d.message.includes('wrapped callable')&&d.message.includes('outside::library')));
  const wrappedCall=analyze('<p>{{ captured.read() }}</p>', 'import {snapshot} from "weiv:observable"; import {library} from "outside"; const captured=snapshot({read:()=>library.count});').entries;
  assert(wrappedCall.some(d=>d.message.includes('outside::library')));
  assert.deepEqual(analyze('<p>{{ captured.count }}</p>', 'import {snapshot} from "weiv:observable"; import {library} from "outside"; const captured=snapshot({count:1,read:()=>library.count});').entries,[]);
  assert.deepEqual(analyze('<p>{{ state.count }}</p>', 'import {library} from "outside"; const state={count:1,read:()=>library.count};').entries,[]);
  assert.deepEqual(analyze('<p>{{ captured.double(2) }}</p>', 'import {snapshot} from "weiv:observable"; const captured=snapshot({double:value=>value*2});').entries,[]);
  assert(analyze('<p>{{ captured.read() }}</p>', 'import {snapshot} from "weiv:observable"; let count=0; function read(){return count++} const captured=snapshot({read});').entries.some(d=>d.message.includes('render effects are unverified')));
  assert.deepEqual(analyze('<p>{{ captured[0].count }} {{ captured.map(row=>row.count).join(",") }}</p>', 'import {snapshot} from "weiv:observable"; const captured=snapshot([{count:1}]);').entries,[]);
  assert(analyze('<p>{{ captured[0].count }}</p>', 'import {snapshot} from "weiv:observable"; const callback=()=>0; const captured=snapshot([callback]);').entries.some(d=>d.message.includes('callable properties')));
  file("dynamic.ts", 'import {observable} from "weiv:observable"; export let state=observable({count:0}); eval("state={count:1}");');
  assert.equal(analyze("<p>{{ state.count }}</p>", 'import {state} from "./dynamic";').entries[0].code, "reactivity.untracked_external_state");

  mkdirSync(join(dir, "folder"));
  file("folder/index.ts", "export const value=7;");
  assert.deepEqual(analyze("<p>{{ value }}</p>", 'import {value} from "./folder";').entries, []);
  file("large.ts", `/*${"x".repeat(1024 * 1024)}*/ export const state={count:0};`);
  file("large.ts.ts", 'import {observable} from "weiv:observable"; export const state=observable({count:0});');
  assert.equal(analyze("<p>{{ state.count }}</p>", 'import {state} from "./large.ts";').entries[0].code, "reactivity.unverified_dependency");

  assert.equal(analyze("<p>{{ Counter.count }}</p>", "const Counter=class { static count=0; };").entries[0].code, "reactivity.unverified_dependency");
  assert.equal(analyze("<p>{{ helper.label }}</p>", 'function helper(){return 1} helper.label="initial";').entries[0].code, "reactivity.unverified_dependency");
  assert.equal(analyze("<p>{{ core.label }}</p>", 'import {observable as core} from "weiv:observable";').entries[0].code, "reactivity.unverified_dependency");
  assert.equal(analyze("<p>{{ helper() }}</p>", 'function helper(){return helper.label} helper.label="initial";').entries[0].code, "reactivity.unverified_dependency");
  const globalRead = analyze("<p>{{ read() }}</p>", "function read(){return globalThis.store.count}").entries;
  assert.equal(globalRead[0].code, "reactivity.unverified_dependency");
  assert(globalRead[0].message.includes("global::globalThis.store.count"));
  assert.deepEqual(analyze("<p>{{ size(data) }}</p>", "const data={a:1}; function size(value){return Object.keys(value).length}").entries, []);
  assert.deepEqual(analyze('<p>{{ keys.join(",") }} {{ count }}</p>', 'const data={a:1}; const keys=Object.keys(data); const count=Number(2);').entries,[]);

  file("default-collision.ts", 'import {observable} from "weiv:observable"; const $default=observable({count:0}); export default {count:1};');
  assert.equal(analyze("<p>{{ state.count }}</p>", 'import state from "./default-collision";').entries[0].code, "reactivity.untracked_external_state");
  const opaque = analyze("<p>{{ store.count }}</p>", 'import {store} from "third-party";').entries;
  assert.equal(opaque.length, 1);
  assert.equal(opaque[0].code, "reactivity.unverified_dependency");
  assert(opaque[0].message.includes("third-party"));
  console.log("State-boundary tracing, source locations, observable contracts, shadowing and cycle diagnostics pass");
} finally { rmSync(dir, { recursive: true, force: true }); }
