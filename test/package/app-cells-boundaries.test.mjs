import assert from 'node:assert/strict';
import {spawnSync} from 'node:child_process';
import {mkdtempSync,mkdirSync,writeFileSync,readFileSync,readdirSync,symlinkSync,rmSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {join,resolve} from 'node:path';
import {pathToFileURL} from 'node:url';
import {JSDOM} from 'jsdom';
const root=resolve(import.meta.dirname,'../..');
const binary=process.env.WEIV_BINARY_PATH||join(root,'zig-out/bin/weiv');
const temp=mkdtempSync(join(tmpdir(),'weiv-app-boundary-'));
const project=join(temp,'project'),output=join(temp,'dist');mkdirSync(project);
const previous={window:globalThis.window,document:globalThis.document};let dom,handle;
try {
  writeFileSync(join(temp,'library.ts'), `import {observable} from 'weiv:observable';
    export const raw={count:0}; export const observed=observable({count:0,read(){return [{valueOf:()=>this.count}]}});
    const hidden=observable({count:0}); export function read(){return hidden.count}
    export function mutate(){raw.count++; observed.count++; hidden.count++}
    export function invoke(callback,value){return callback(value)}
    export const label='fixed';`);
  symlinkSync('../library.ts',join(project,'library-alias.ts'));
  const component=join(project,'App.weiv');
  writeFileSync(component,`<template><p class="raw">{{ raw.count }}</p><p class="observed">{{ observed.count }}</p><p class="hidden">{{ read() }}</p><p class="json">{{ JSON.stringify(view) }}</p><p class="helper">{{ localRead() }}</p><p class="forwarded">{{ invoke(value=>value.count,observed) }}</p><p class="captured-forwarded">{{ invoke(localRead) }}</p><p class="method-forwarded">{{ Math.max(...invoke(value=>value.read(),observed)) }}</p></template><script lang="ts">import {raw,observed,read,invoke} from './library-alias.ts'; const view={toJSON:()=>({count:observed.count})}; function localRead(){return observed.count}</script>`);
  const result=spawnSync(binary,['--json-diagnostics','emit','app-cells',component,output],{cwd:root,encoding:'utf8'});
  assert.equal(result.status,0,result.stderr);
  const report=JSON.parse(result.stderr);
  assert.equal(report.mode,'managed-project');
  assert.equal(report.diagnostics.length,2,JSON.stringify(report.diagnostics));
  assert(report.diagnostics.some(d=>d.code==='reactivity.untracked_external_state'&&d.message.includes('library.ts::raw')));
  assert(report.diagnostics.some(d=>d.code==='reactivity.unverified_dependency'&&d.message.includes('subscription path')));
  assert(report.diagnostics.every(d=>d.sourcePath.endsWith('App.weiv')&&d.span&&d.location&&d.message.includes('observable or subscription adapter')));
  assert.equal(readdirSync(join(output,'__weiv_modules')).filter(file=>file.endsWith('.publisher.mjs')).length,0,'A symlink must not turn an unmanaged source into managed state');
  const libraryFile=readdirSync(join(output,'__weiv_modules')).find(file=>readFileSync(join(output,'__weiv_modules',file),'utf8').includes('export const raw'));
  const library=await import(pathToFileURL(join(output,'__weiv_modules',libraryFile)));
  dom=new JSDOM('<main></main>');globalThis.window=dom.window;globalThis.document=dom.window.document;
  const app=await import(pathToFileURL(join(output,'bundle.mjs')));
  const target=document.querySelector('main');handle=app.mount(target,{});
  library.mutate();await new Promise(resolve=>queueMicrotask(resolve));
  assert.equal(target.querySelector('.observed').textContent,'1');
  assert.equal(target.querySelector('.json').textContent,'{"count":1}');
  assert.equal(target.querySelector('.helper').textContent,'1');
  assert.equal(target.querySelector('.forwarded').textContent,'1');
  assert.equal(target.querySelector('.captured-forwarded').textContent,'1');
  assert.equal(target.querySelector('.method-forwarded').textContent,'1');
  assert.equal(target.querySelector('.raw').textContent,'0');
  assert.equal(target.querySelector('.hidden').textContent,'0');
  handle.destroy();handle=undefined;

  // Reflective destination flows must warn even though ordinary writes through
  // the normalized state still update. Retained foreign raw aliases stay raw.
  writeFileSync(join(temp,'foreign.ts'),`export const child={count:1}; export function bump(){child.count++}`);
  writeFileSync(join(project,'managed-state.ts'),`import {child} from '../foreign.ts';
    export const state={child:{count:0}};
    export function replace(){const args=[state,{child}];Reflect.apply(Object.assign,null,args)}`);
  const reflective=join(project,'Reflective.weiv'),reflectiveOutput=join(temp,'reflective-output');
  writeFileSync(reflective,`<template><p>{{ state.child.count }}</p></template><script lang="ts">import {state} from './managed-state.ts';</script>`);
  const reflectiveBuild=spawnSync(binary,['--json-diagnostics','emit','app-cells',reflective,reflectiveOutput],{cwd:root,encoding:'utf8'});
  assert.equal(reflectiveBuild.status,0,reflectiveBuild.stderr);
  const reflectiveReport=JSON.parse(reflectiveBuild.stderr);
  assert(reflectiveReport.diagnostics.some(d=>d.code==='reactivity.unverified_dependency'&&d.message.includes('Reflect.apply')&&d.message.includes('managed-state.ts::state')));
  const moduleDirectory=join(reflectiveOutput,'__weiv_modules');
  const managedFile=readdirSync(moduleDirectory).find(file=>readFileSync(join(moduleDirectory,file),'utf8').includes('function replace('));
  const foreignFile=readdirSync(moduleDirectory).find(file=>readFileSync(join(moduleDirectory,file),'utf8').includes('function bump('));
  const managedState=await import(pathToFileURL(join(moduleDirectory,managedFile)));
  const foreign=await import(pathToFileURL(join(moduleDirectory,foreignFile)));
  const reflectiveApp=await import(pathToFileURL(join(reflectiveOutput,'bundle.mjs')));
  handle=reflectiveApp.mount(target,{});
  assert.equal(target.querySelector('p').textContent,'0');
  managedState.replace();await new Promise(resolve=>queueMicrotask(resolve));
  assert.equal(target.querySelector('p').textContent,'1');
  foreign.bump();await new Promise(resolve=>queueMicrotask(resolve));
  assert.equal(managedState.state.child.count,2);
  assert.equal(target.querySelector('p').textContent,'1','retained foreign raw writes remain outside the tracking boundary');
  handle.destroy();handle=undefined;

  // Unused and event-only mutable imports do not produce blanket library warnings.
  const quiet=join(project,'Quiet.weiv');
  writeFileSync(quiet,`<template><button @click="mutate">Go</button><p>{{ label }}</p></template><script lang="ts">import {label,raw,mutate} from './library-alias.ts';</script>`);
  const quietBuild=spawnSync(binary,['compile','emit','app-cells',quiet,join(temp,'quiet')],{cwd:root,encoding:'utf8'});
  assert.equal(quietBuild.status,0,quietBuild.stderr);assert.equal(quietBuild.stderr,'');
  writeFileSync(join(project,'opaque.ts'),`export const label='fixed'; export function load(name){return import(name)}`);
  const opaque=join(project,'Opaque.weiv');
  writeFileSync(opaque,`<template><p>{{ label }}</p></template><script lang="ts">import {label} from './opaque.ts';</script>`);
  const rejected=spawnSync(binary,['--json-diagnostics','emit','app-cells',opaque,join(temp,'opaque-output')],{cwd:root,encoding:'utf8'});
  assert.notEqual(rejected.status,0);
  const failure=JSON.parse(rejected.stderr);
  assert(JSON.stringify(failure).includes('OpaqueDynamicModuleImportUnsupported'));
  console.log('Managed builds preserve canonical external boundaries, explicit observables, warning spans and event-only silence');
} finally {
  handle?.destroy();dom?.window.close();globalThis.window=previous.window;globalThis.document=previous.document;
  rmSync(temp,{recursive:true,force:true});
}
