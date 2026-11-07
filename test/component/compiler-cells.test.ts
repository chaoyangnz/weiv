import { expect, test } from "bun:test";
import { mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { pathToFileURL } from "node:url";
import { execFileSync } from "node:child_process";
import { installJsdom, loadModules } from "./support";

const tick = () => new Promise<void>(resolve => queueMicrotask(resolve));
function emit(path: string) {
  return Bun.spawnSync(["zig", "build", "run", "--", "emit", "js", path], { stdout: "pipe", stderr: "pipe" });
}
async function fixture(path = "test/examples/basic/compiler-cells.weiv") {
  const result = emit(path);
  if (result.exitCode) throw new Error(new TextDecoder().decode(result.stderr));
  const runtime = pathToFileURL(join(process.cwd(), "packages/weiv/src/runtime/cell.ts")).href;
  const observableRuntime = pathToFileURL(join(process.cwd(), "packages/weiv/src/runtime/observable.ts")).href;
  const code = new TextDecoder().decode(result.stdout).replace('"weiv:cells"', JSON.stringify(runtime)).replace('"weiv:observable"', JSON.stringify(observableRuntime));
  const modules = await loadModules({ "CompilerCells.mjs": code });
  const previousWindow = (globalThis as any).window;
  const { document, window } = installJsdom();
  (globalThis as any).window = window;
  const handles: any[] = [];
  const mount = (initial = 0) => {
    const target = document.createElement("div");
    document.body.append(target);
    const handle = modules["CompilerCells.mjs"].mount(target, { initial });
    handles.push(handle);
    return { target, handle, text: (selector: string) => target.querySelector(selector)?.textContent };
  };
  return {
    mount,
    send: (name: string, detail: any = {}) => {
      window.dispatchEvent(new window.CustomEvent(name, { detail }));
      return detail;
    },
    close: () => {
      for (const handle of handles) if (!handle.instance.destroyed) handle.destroy();
      window.close();
      (globalThis as any).window = previousWindow;
    },
    window,
  };
}

test("experimental compiler cells update external writes and preserve lexical shadowing", async () => {
  const f = await fixture();
  try {
    const view = f.mount();
    expect(view.text(".shadow")).toBe("41");
    f.send("cells-write");
    await tick();
    expect(view.text(".count")).toBe("1");
    expect(view.text(".object")).toBe("1");
    expect(view.text(".shadow")).toBe("41");
    view.target.querySelector("button")!.dispatchEvent(new f.window.Event("click"));
    await tick();
    expect(view.text(".count")).toBe("2");
  } finally { f.close(); }
}, 30000);

test("experimental cells repaint between awaits and from detached promises", async () => {
  const f = await fixture();
  try {
    const view = f.mount();
    let first!: () => void, second!: () => void;
    const detail = f.send("cells-async", {
      first: new Promise<void>(resolve => { first = resolve; }),
      second: new Promise<void>(resolve => { second = resolve; }),
    });
    await tick();
    expect(view.text(".count")).toBe("1");
    first(); await tick(); await tick();
    expect(view.text(".count")).toBe("2");
    second(); await detail.result; await tick();
    expect(view.text(".count")).toBe("3");
    f.send("cells-detached"); await tick(); await tick();
    expect(view.text(".count")).toBe("4");
  } finally { f.close(); }
}, 30000);

test("experimental writes notify between awaits and survive rejection and finally", async () => {
  const dir = mkdtempSync(join(tmpdir(), "weiv-cells-rejection-"));
  const path = join(dir, "Rejection.weiv");
  writeFileSync(path, `<template><p>{{ count }} / {{ other }} / {{ state.n }} / {{ rest.length }}</p></template><script lang="ts">
    let count=0;let other=0;let state={n:0};let rest=[];
    window.addEventListener('cells-reject',event=>{event.detail.task=(async()=>{
      try {
        count++;state.n++;
        await event.detail.first;
        ({a:count,b:other}={a:3,b:4});state={n:5};
        await event.detail.second;
        [count,other,...rest]=[6,7,8];state.n++;
        throw event.detail.error;
      } finally {state.n++;}
    })();});
  </script>`);
  try {
    for (const failure of ["first", "second", "throw"]) {
      const f = await fixture(path);
      try {
        const view = f.mount();
        let releaseFirst!: () => void, releaseSecond!: () => void;
        let rejectFirst!: (error: Error) => void, rejectSecond!: (error: Error) => void;
        const first = new Promise<void>((resolve, reject) => { releaseFirst = resolve; rejectFirst = reject; });
        const second = new Promise<void>((resolve, reject) => { releaseSecond = resolve; rejectSecond = reject; });
        const error = new Error(failure);
        const detail = f.send("cells-reject", { first, second, error });
        let settled = false;
        const caught = detail.task.catch((reason: Error) => { settled = true; return reason; });
        await tick();
        expect(view.text("p")).toBe("1 / 0 / 1 / 0");
        expect(settled).toBe(false);
        if (failure === "first") rejectFirst(error);
        else {
          releaseFirst();await tick();await tick();
          expect(view.text("p")).toBe("3 / 4 / 5 / 0");
          expect(settled).toBe(false);
          if (failure === "second") rejectSecond(error);
          else releaseSecond();
        }
        expect(await caught).toBe(error);
        await tick();
        expect(view.text("p")).toBe(failure === "first" ? "1 / 0 / 2 / 0" : failure === "second" ? "3 / 4 / 6 / 0" : "6 / 7 / 7 / 1");
      } finally { f.close(); }
    }
  } finally { rmSync(dir, { recursive: true, force: true }); }
}, 30000);

test("experimental subscriptions and timer names preserve user lexical bindings", async () => {
  const dir = mkdtempSync(join(tmpdir(), "weiv-cells-helper-names-"));
  const path = join(dir, "Names.weiv");
  writeFileSync(path, `<template><p>{{ scope.n }} / {{ instance }} / {{ Array }} / {{ count }}</p>
    <button @click="(setTimeout(()=>count++),setInterval(()=>count++),queueMicrotask(()=>count++),requestAnimationFrame(value=>count+=value))">go</button>
  </template><script lang="ts">
    let scope={n:0};let instance=0;let Array=0;let count=0;
    function setTimeout(callback){scope.n++;return callback()}
    function setInterval(callback){instance++;return callback()}
    function queueMicrotask(callback){Array++;return callback()}
    function requestAnimationFrame(callback){return callback(7)}
  </script>`);
  try {
    const f = await fixture(path);
    try {
      const view = f.mount();
      expect(view.text("p")).toBe("0 / 0 / 0 / 0");
      view.target.querySelector("button")!.dispatchEvent(new f.window.Event("click"));
      expect(view.text("p")).toBe("0 / 0 / 0 / 0");
      await tick();
      expect(view.text("p")).toBe("1 / 1 / 1 / 10");
    } finally { f.close(); }
  } finally { rmSync(dir, { recursive: true, force: true }); }
}, 30000);


test("experimental lowering preserves expression results, shorthand and call receivers", async () => {
  const f = await fixture();
  try {
    const view = f.mount();
    const detail = f.send("cells-expression");
    await tick();
    expect(detail.post).toBe(0);
    expect(detail.pre).toBe(2);
    expect(detail.shorthand).toEqual({ count: 2 });
    expect(detail.receiver).toBe(true);
    expect(detail.parenthesizedReceiver).toBe(true);
    expect(detail.sequenceReceiver).toBe(true);
    expect(detail.optional).toBeUndefined();
    expect(detail.nonCallable).toBe(true);
    expect(detail.argumentCalls).toBe(1);
    expect(view.text(".count")).toBe("8");
    expect(view.text(".object")).toBe("8");
  } finally { f.close(); }
}, 30000);

test("experimental object replacement tracks new members and detaches old aliases", async () => {
  const f = await fixture();
  try {
    const view = f.mount();
    const detail = f.send("cells-replace");
    await tick();
    expect(view.text(".object")).toBe("11");
    let updates = 0;
    const original = view.handle.instance.updateDirty;
    view.handle.instance.updateDirty = (...args: any[]) => { updates++; return original(...args); };
    detail.old.n++;
    await tick();
    expect(updates).toBe(0);
    f.send("cells-write"); await tick();
    expect(view.text(".object")).toBe("12");
  } finally { f.close(); }
}, 30000);

test("experimental instances isolate queued updates and destruction", async () => {
  const f = await fixture();
  try {
    const a = f.mount(0), b = f.mount(10);
    f.send("cells-write");
    a.handle.destroy();
    await tick();
    expect(a.target.textContent).toBe("");
    expect(b.text(".count")).toBe("11");
    f.send("cells-write"); await tick();
    expect(a.target.textContent).toBe("");
    expect(b.text(".count")).toBe("12");
  } finally { f.close(); }
}, 30000);

test("experimental cells retain writes before exceptions", async () => {
  const f = await fixture();
  try {
    const view = f.mount();
    const error = new Error("expected");
    expect(f.send("cells-throw", { error }).caught).toBe(error);
    await tick();
    expect(view.text(".count")).toBe("1");
  } finally { f.close(); }
}, 30000);

test("destructuring assignments preserve native order, rest and expression results",async()=>{
  const dir=mkdtempSync(join(tmpdir(),"weiv-pattern-writes-"));const path=join(dir,"Patterns.weiv");
  const script=`let count=0;let other=0;let rest=[];const state={n:0};
    window.addEventListener('cells-write',event=>{const trace=[];const rhs={get a(){trace.push('get-a');return 3},get nested(){trace.push('get-nested');return {value:4}},extra:5};
      const result=({[(trace.push('key'),'a')]:count,nested:{value:other},...rest}=rhs);
      const array=[6,undefined,8,9];const returned=([count,other=(trace.push('default'),7),...rest]=array);
      ({count}= {count:count+1});({value:state.n}={value:10});
      for([count] of [[11],[12]])trace.push('loop-'+count);
      for(other in {first:1,last:2})trace.push(other);
      function shadow(count){({count}={count:99});return count}
      event.detail.result={trace,same:result===rhs&&returned===array,count,other,rest:[...rest],n:state.n,shadow:shadow(1)};
    });`;
  writeFileSync(path,`<template><p>{{ count }} / {{ other }} / {{ rest.length }} / {{ state.n }}</p></template><script lang="ts">${script}</script>`);
  const nativeHandlers=new Map<string,Function>();new Function('window','"use strict";'+script)({addEventListener:(name:string,fn:Function)=>nativeHandlers.set(name,fn)});
  const native:any={detail:{}};nativeHandlers.get('cells-write')!(native);
  try {const f=await fixture(path);try {const view=f.mount();const detail=f.send('cells-write');await tick();
    expect(detail.result).toEqual(native.detail.result);expect(detail.result.same).toBe(true);expect(view.target.textContent).toBe('12 / last / 2 / 10');
  }finally{f.close();}}finally{rmSync(dir,{recursive:true,force:true});}
},30000);

test("partial destructuring writes notify before getter and iterator failures",async()=>{
  const dir=mkdtempSync(join(tmpdir(),"weiv-pattern-exceptions-"));const path=join(dir,"Exceptions.weiv");
  const script=`let count=0;let other=0;window.addEventListener('cells-write',event=>{const trace=[];
    const source={get count(){trace.push('first');return 7},get other(){trace.push('throw');throw Error('getter')}};
    try{({count,other}=source)}catch(error){trace.push(error.message)}
    const input={[Symbol.iterator](){let step=0;return {next(){trace.push('next');return {done:false,value:++step===1?8:undefined}},return(){trace.push('close');return {done:true}}}}};
    try{[count,other=(()=>{throw Error('default')})()]=input}catch(error){trace.push(error.message)}
    event.detail.result={trace,count,other};});`;
  writeFileSync(path,`<template><p>{{ count }} / {{ other }}</p></template><script lang="ts">${script}</script>`);
  const handlers=new Map<string,Function>();new Function('window','"use strict";'+script)({addEventListener:(name:string,fn:Function)=>handlers.set(name,fn)});
  const native:any={detail:{}};handlers.get('cells-write')!(native);
  try {const f=await fixture(path);try {const view=f.mount();const detail=f.send('cells-write');await tick();expect(detail.result).toEqual(native.detail.result);expect(view.target.textContent).toBe('8 / 0');}finally{f.close();}}
  finally{rmSync(dir,{recursive:true,force:true});}
},30000);

test("assignment targets preserve early-write timing and anonymous default names",async()=>{
  const dir=mkdtempSync(join(tmpdir(),"weiv-pattern-names-"));const path=join(dir,"Names.weiv");
  const script=`const trace=[];
    try{count=(trace.push('rhs'),1)}catch(error){trace.push(error.name)}
    try{({count}={get count(){trace.push('get');return 2}})}catch(error){trace.push(error.name)}
    try{count||=(trace.push('skipped'),3)}catch(error){trace.push(error.name)}
    let count=0;window.addEventListener('cells-write',event=>{const source={};const first=({count=()=>count}=source);const previous=count;
      ({value:count=class {static label=this.name;static previous=count}}={});
      event.detail.result={trace:[...trace],same:first===source,name:count.name,label:count.label,previous:count.previous===previous};});`;
  const typed=script.replace("count=(trace.push('rhs'),1)","(count as number)=(trace.push('rhs'),1)");
  writeFileSync(path,`<template><p>{{ typeof count }}</p></template><script lang="ts">${typed}</script>`);
  // Bun 1.2.16 differs on class property naming and new Function TDZ timing.
  // Run both the native oracle and the mounted generated module under Node.
  try{
    const result=emit(path);expect(result.exitCode).toBe(0);
    const runtime=pathToFileURL(join(process.cwd(),'packages/weiv/src/runtime/cell.ts')).href;
    const compiled=join(dir,'compiled.mjs');
    writeFileSync(compiled,new TextDecoder().decode(result.stdout).replace('"weiv:cells"',JSON.stringify(runtime)));
    const runner=join(dir,'check.mjs');
    writeFileSync(runner,`import assert from 'node:assert/strict';
      import {JSDOM} from ${JSON.stringify(import.meta.resolve('jsdom'))};
      import {mount} from './compiled.mjs';
      const handlers=new Map();new Function('window','"use strict";'+${JSON.stringify(script)})({addEventListener:(name,fn)=>handlers.set(name,fn)});
      const native={detail:{}};handlers.get('cells-write')(native);
      const dom=new JSDOM('<main></main>');globalThis.window=dom.window;globalThis.document=dom.window.document;
      const target=document.querySelector('main');const handle=mount(target,{});
      const detail={};window.dispatchEvent(new window.CustomEvent('cells-write',{detail}));await new Promise(resolve=>queueMicrotask(resolve));
      assert.deepEqual(detail.result,native.detail.result);assert.equal(detail.result.name,'count');assert.equal(target.textContent,'function');
      handle.destroy();dom.window.close();`);
    execFileSync('node',[runner],{stdio:'pipe'});
  }
  finally{rmSync(dir,{recursive:true,force:true});}
},30000);

test("destructuring declarations initialize each binding before subsequent extraction",async()=>{
  const dir=mkdtempSync(join(tmpdir(),"weiv-declaration-"));const path=join(dir,"Declaration.weiv");
  const script=`const trace=[];
    const source={get first(){trace.push('first');return 1},get next(){trace.push('next-'+count);return undefined},tail:3};
    let {first:count,[(trace.push('key-'+count),'next')]:other=count+1,...rest}=source;
    const original={n:4};let [state,,...rows]=[original,99,{n:5},{n:6}];
    const {fixed={n:7}}={};
    let {__proto__=0}=Object.create(null);
    let {fn=()=>count}={};let {cls=class {static label=this.name;static before=fn.name}}={};
    window.addEventListener('cells-proto',()=>{__proto__++});
    window.addEventListener('cells-write',event=>{count++;other++;original.n++;rows[0].n++;rest.tail++;fixed.n++;__proto__++;
      event.detail.result={trace:[...trace],same:state===original,proto:__proto__,count,other,n:state.n,rows:rows.map(x=>x.n),tail:rest.tail,fixed:fixed.n,fn:fn.name,cls:cls.name,label:cls.label,before:cls.before};});`;
  writeFileSync(path,`<template><p>{{ count }} / {{ other }} / {{ state.n }} / {{ rows[0].n }} / {{ rest.tail }} / {{ fixed.n }} / {{ fn.name }} / {{ cls.name }} / {{ __proto__ }}</p></template><script lang="ts">${script}</script>`);
  try{
    const result=emit(path);if(result.exitCode)throw Error(new TextDecoder().decode(result.stderr));
    const runtime=pathToFileURL(join(process.cwd(),'packages/weiv/src/runtime/cell.ts')).href;
    writeFileSync(join(dir,'compiled.mjs'),new TextDecoder().decode(result.stdout).replace('"weiv:cells"',JSON.stringify(runtime)));
    const runner=join(dir,'check.mjs');
    writeFileSync(runner,`import assert from 'node:assert/strict';import {JSDOM} from ${JSON.stringify(import.meta.resolve('jsdom'))};import {mount} from './compiled.mjs';
      const handlers=new Map();new Function('window','"use strict";'+${JSON.stringify(script)})({addEventListener:(name,fn)=>handlers.set(name,fn)});const native={detail:{}};handlers.get('cells-write')(native);
      const dom=new JSDOM('<main></main>');globalThis.window=dom.window;globalThis.document=dom.window.document;const target=document.querySelector('main');const handle=mount(target,{});
      const detail={};window.dispatchEvent(new window.CustomEvent('cells-write',{detail}));await new Promise(resolve=>queueMicrotask(resolve));
      assert.deepEqual(detail.result,native.detail.result);assert.equal(target.textContent,'2 / 3 / 5 / 6 / 4 / 8 / fn / cls / 1');
      window.dispatchEvent(new window.Event('cells-proto'));await new Promise(resolve=>queueMicrotask(resolve));assert.equal(target.textContent,'2 / 3 / 5 / 6 / 4 / 8 / fn / cls / 2');
      handle.destroy();dom.window.close();`);
    execFileSync('node',[runner],{stdio:'pipe'});
  }finally{rmSync(dir,{recursive:true,force:true});}
},30000);

test("inline template writes use script cells and retain native results",async()=>{
  const dir=mkdtempSync(join(tmpdir(),"weiv-inline-writes-"));const path=join(dir,"Inline.weiv");
  writeFileSync(path,`<template>
    <p>{{ count }} / {{ other }} / {{ state.n }} / {{ read() }}</p>
    <button id="increment" @click="(count++,state.n++,event.detail.result=count)">increment</button>
    <button id="replace" @click="(event.detail.result=(state={n:10}),event.detail.same=event.detail.result===state)">replace</button>
    <button id="pattern" @click="event.detail.result=({count,other}=event.detail.input)">pattern</button>
    <button id="function" @click="read=()=>count+100">function</button>
    <button id="async" @click="event.detail.task=(async()=>{count=1;await event.detail.wait;count=2})()">async</button>
    <button id="delete" @click="event.detail.result=delete state.n">delete</button>
  </template><script lang="ts">let count=0;let other=0;let state={n:0};let read=()=>count;</script>`);
  try{const f=await fixture(path);try{const view=f.mount();
    const click=(id:string,detail:any={})=>{view.target.querySelector('#'+id)!.dispatchEvent(new f.window.CustomEvent('click',{detail}));return detail};
    const first=click('increment');await tick();expect(first.result).toBe(1);expect(view.target.querySelector('p')!.textContent).toBe('1 / 0 / 1 / 1');
    const replaced=click('replace');await tick();expect(replaced.same).toBe(true);expect(replaced.result.n).toBe(10);
    replaced.result.n++;await tick();expect(view.target.querySelector('p')!.textContent).toBe('1 / 0 / 11 / 1');
    const input={count:7,other:3};const pattern=click('pattern',{input});await tick();expect(pattern.result).toBe(input);expect(view.target.querySelector('p')!.textContent).toBe('7 / 3 / 11 / 7');
    click('function');await tick();expect(view.target.querySelector('p')!.textContent).toBe('7 / 3 / 11 / 107');
    let release!:()=>void;const delayed=click('async',{wait:new Promise<void>(resolve=>release=resolve)});await tick();expect(view.target.querySelector('p')!.textContent).toBe('1 / 3 / 11 / 101');
    release();await delayed.task;await tick();expect(view.target.querySelector('p')!.textContent).toBe('2 / 3 / 11 / 102');
    const removed=click('delete');await tick();expect(removed.result).toBe(true);expect(view.target.querySelector('p')!.textContent).toBe('2 / 3 /  / 102');
  }finally{f.close();}}finally{rmSync(dir,{recursive:true,force:true});}
},30000);

test("experimental setup preserves multiline literals in script and template closures", async () => {
  const dir = mkdtempSync(join(tmpdir(), "weiv-multiline-literals-"));
  const path = join(dir, "Literals.weiv");
  const scriptText = "start\n  import literal text\n    export literal text\nend";
  const templateText = "template\n  import template text\n    export template text\nend";
  const eventText = "event\n  import event text\n    export event text\nend";
  writeFileSync(path, [
    '<template><pre id="script">{{ value }}</pre>',
    '<pre id="template">{{ `' + templateText + '` }}</pre>',
    '<button @click="value=`' + eventText + '`">change</button></template>',
    '<script lang="ts">export let props={}; let value=`' + scriptText + '`;</script>',
  ].join("\n"));
  try {
    const f = await fixture(path);
    try {
      const view = f.mount();
      expect(view.text("#script")).toBe(scriptText);
      expect(view.text("#template")).toBe(templateText);
      view.target.querySelector("button")!.dispatchEvent(new f.window.Event("click"));
      await tick();
      expect(view.text("#script")).toBe(eventText);
    } finally { f.close(); }
  } finally { rmSync(dir, { recursive: true, force: true }); }
}, 30000);

test("inline events preserve loop aliases, script shadows and callback parameters",async()=>{
  const dir=mkdtempSync(join(tmpdir(),"weiv-inline-scopes-"));const path=join(dir,"Scopes.weiv");
  writeFileSync(path,`<template>
    <p class="root">{{ row }} / {{ count }}</p>
    <section #for="row in rows"><p class="outer">{{ row.n }}</p><button class="outer-write" @click="row.n++">outer</button>
      <div #for="row in row.children"><p class="inner">{{ row.n }}</p><button class="inner-write" @click="()=>row.n++">inner</button></div>
    </section>
    <section #for="event in events"><p class="event-value">{{ event.n }}</p><button class="event-write" @click="event.n++">event</button></section>
    <button class="parameter" @click="event.detail.value=((row)=>row+1)(40)">parameter</button>
  </template><script lang="ts">let row=99;let count=0;const rows=[{n:1,children:[{n:2}]}];const events=[{n:4}];</script>`);
  try{const f=await fixture(path);try{const view=f.mount();
    for(const name of ['outer','inner','event']){view.target.querySelector('.'+name+'-write')!.dispatchEvent(new f.window.Event('click'));await tick();}
    expect(view.target.querySelector('.outer')!.textContent).toBe('2');expect(view.target.querySelector('.inner')!.textContent).toBe('3');expect(view.target.querySelector('.event-value')!.textContent).toBe('5');
    const detail:any={};view.target.querySelector('.parameter')!.dispatchEvent(new f.window.CustomEvent('click',{detail}));expect(detail.value).toBe(41);expect(view.target.querySelector('.root')!.textContent).toBe('99 / 0');
  }finally{f.close();}}finally{rmSync(dir,{recursive:true,force:true});}
},30000);

test("replacing local aliases releases old graphs and keeps scalar snapshots ordinary",async()=>{
  const dir=mkdtempSync(join(tmpdir(),"weiv-alias-lifetime-"));const path=join(dir,"Aliases.weiv");
  writeFileSync(path,`<template><p>{{ state.n }} / {{ captured }}</p><button @click="state=replacement">replace</button></template><script lang="ts">
    const original={n:0};const replacement={n:10};let state=original;let source=1;const captured=source;
    window.addEventListener('old-write',()=>original.n++);window.addEventListener('new-write',()=>replacement.n++);window.addEventListener('scalar-write',()=>source++);
  </script>`);
  try{const f=await fixture(path);try{const view=f.mount();let updates=0;const originalUpdate=view.handle.instance.updateDirty;view.handle.instance.updateDirty=(...args:any[])=>{updates++;return originalUpdate(...args)};
    f.send('old-write');await tick();expect(view.target.querySelector('p')!.textContent).toBe('1 / 1');expect(updates).toBe(1);
    view.target.querySelector('button')!.dispatchEvent(new f.window.Event('click'));await tick();expect(view.target.querySelector('p')!.textContent).toBe('10 / 1');const after=updates;
    f.send('old-write');f.send('scalar-write');await tick();expect(updates).toBe(after);expect(view.target.querySelector('p')!.textContent).toBe('10 / 1');
    f.send('new-write');await tick();expect(updates).toBe(after+1);expect(view.target.querySelector('p')!.textContent).toBe('11 / 1');
  }finally{f.close();}}finally{rmSync(dir,{recursive:true,force:true});}
},30000);

test("replaced callable state subscribes to newly captured roots",async()=>{
  const dir=mkdtempSync(join(tmpdir(),"weiv-callable-state-"));const path=join(dir,"Callable.weiv");
  writeFileSync(path,`<template><p>{{ read() }}</p><button @click="read=()=>other">replace</button></template><script lang="ts">
    let other=0;let read=()=>0;window.addEventListener('callable-next',()=>other++);window.addEventListener('callable-reset',()=>{read=()=>other+10});
  </script>`);
  try{const f=await fixture(path);try{const view=f.mount();view.target.querySelector('button')!.dispatchEvent(new f.window.Event('click'));await tick();f.send('callable-next');await tick();expect(view.target.querySelector('p')!.textContent).toBe('1');
    f.send('callable-reset');await tick();expect(view.target.querySelector('p')!.textContent).toBe('11');f.send('callable-next');await tick();expect(view.target.querySelector('p')!.textContent).toBe('12');
  }finally{f.close();}}finally{rmSync(dir,{recursive:true,force:true});}
},30000);

test("inline handler references keep receivers and expression results are not invoked twice",async()=>{
  const dir=mkdtempSync(join(tmpdir(),"weiv-handler-values-"));const path=join(dir,"Handlers.weiv");
  writeFileSync(path,`<template><p>{{ count }} / {{ holder.n }}</p>
    <button id="install" @click="callback=()=>count++">install</button><button id="invoke" @click="callback">invoke</button>
    <button id="factory" @click="factory()">factory</button><button id="method" @click="holder.read">method</button>
    <button id="disabled" @click="false && callback">disabled</button><button id="optional" @click="missing?.read">optional</button>
  </template><script lang="ts">let count=0;let callback=()=>0;const holder={n:0,read(event){this.n++;event.detail.same=this===holder}};const missing=null;function factory(){return ()=>count++}</script>`);
  try{const f=await fixture(path);try{const view=f.mount();const click=(id:string,detail:any={})=>{view.target.querySelector('#'+id)!.dispatchEvent(new f.window.CustomEvent('click',{detail}));return detail};
    click('install');await tick();expect(view.target.querySelector('p')!.textContent).toBe('0 / 0');click('invoke');await tick();expect(view.target.querySelector('p')!.textContent).toBe('1 / 0');
    click('factory');click('disabled');click('optional');await tick();expect(view.target.querySelector('p')!.textContent).toBe('1 / 0');
    const method=click('method');await tick();expect(method.same).toBe(true);expect(view.target.querySelector('p')!.textContent).toBe('1 / 1');
  }finally{f.close();}}finally{rmSync(dir,{recursive:true,force:true});}
},30000);

test("inline computations keep native implementation objects outside observable storage",async()=>{
  const dir=mkdtempSync(join(tmpdir(),"weiv-event-native-"));const path=join(dir,"Native.weiv");
  writeFileSync(path,`<template><p>{{ count }}</p><button @click="count=cache.get('key')">capture</button></template><script lang="ts">const cache=new Map([['key',7]]);let count=0;window.addEventListener('cache-write',()=>cache.set('key',8));</script>`);
  try{const f=await fixture(path);try{const view=f.mount();view.target.querySelector('button')!.dispatchEvent(new f.window.Event('click'));await tick();expect(view.target.querySelector('p')!.textContent).toBe('7');
    f.send('cache-write');await tick();expect(view.target.querySelector('p')!.textContent).toBe('7');view.target.querySelector('button')!.dispatchEvent(new f.window.Event('click'));await tick();expect(view.target.querySelector('p')!.textContent).toBe('8');
  }finally{f.close();}}finally{rmSync(dir,{recursive:true,force:true});}
},30000);

test("experimental emitter rejects unsupported root declarations and dynamic access", () => {
  const dir = mkdtempSync(join(tmpdir(), "weiv-cells-reject-"));
  try {
    for (const [script, diagnostic] of [
      ["var count=0;", "CellVarDeclarationUnsupported"],
      ["var {count}={count:0};", "CellVarDeclarationUnsupported"],
      ["const count=0; ({count}={count:1});", "CellConstAssignmentUnsupported"],
      ["let count=0; eval('count++');", "CellDynamicEvalUnsupported"],
      ["const count=0; count++;", "CellConstAssignmentUnsupported"],
      ["declare let count:number;", "CellAmbientDeclarationUnsupported"],
      ["let count=await Promise.resolve(1);", "CellTopLevelAwaitUnsupported"],
      ["let count=0;for await(const value of []){count=value}", "script.syntax"],
    ]) {
      const path = join(dir, "Unsupported.weiv");
      writeFileSync(path, `<template><p>{{ count }}</p></template><script lang="ts">${script}</script>`);
      const result = emit(path);
      expect(result.exitCode).not.toBe(0);
      expect(new TextDecoder().decode(result.stderr)).toContain(diagnostic);
    }
    const inline = join(dir, "Inline.weiv");
    writeFileSync(inline, '<template><p>{{ count++ }}</p></template><script lang="ts">let count=0;</script>');
    const unsupported = emit(inline);
    expect(unsupported.exitCode).not.toBe(0);
    expect(new TextDecoder().decode(unsupported.stderr)).toContain("CellTemplateMutationUnsupported");
  } finally { rmSync(dir, { recursive: true, force: true }); }
}, 30000);


test("inline writes reject readonly bindings and readonly loop aliases",()=>{
  const dir=mkdtempSync(join(tmpdir(),"weiv-inline-readonly-"));
  writeFileSync(join(dir,'source.ts'),'export let count=0;');
  try{for(const [template,script,error] of [
    ['<button @click="count++">go</button>','const count=0;','CellConstAssignmentUnsupported'],
    ['<button @click="count++">go</button>',"import {count} from './source.ts';",'CellConstAssignmentUnsupported'],
    ['<button #for="row in rows" @click="row++">go</button>','const rows=[1];','CellConstAssignmentUnsupported'],
    ['<button @click="count=()=>1">go</button>','function count(){return 0}','CellTemplateUntrackedAssignmentUnsupported'],
  ]){const path=join(dir,'Readonly.weiv');writeFileSync(path,`<template>${template}</template><script lang="ts">${script}</script>`);const result=emit(path);expect(result.exitCode).not.toBe(0);expect(new TextDecoder().decode(result.stderr)).toContain(error);}}
  finally{rmSync(dir,{recursive:true,force:true});}
},30000);

test("experimental local and imported shared state render once through one scope", async () => {
  const result = emit("test/examples/basic/compiler-cells-import.weiv");
  if (result.exitCode) throw new Error(new TextDecoder().decode(result.stderr));
  const runtime = pathToFileURL(join(process.cwd(), "packages/weiv/src/runtime/cell.ts")).href;
  const observable = pathToFileURL(join(process.cwd(), "packages/weiv/src/runtime/observable.ts")).href;
  const code = new TextDecoder().decode(result.stdout).replace('"weiv:cells"', JSON.stringify(runtime));
  const modules = await loadModules({
    "Mixed.mjs": code,
    "compiler-cells-state.mjs": `import { observable } from ${JSON.stringify(observable)}; export const shared=observable({count:0});`,
  });
  const previousWindow = (globalThis as any).window;
  const { document, window } = installJsdom();
  (globalThis as any).window = window;
  const target = document.createElement("div");
  document.body.append(target);
  const handle = modules["Mixed.mjs"].mount(target, {});
  let updates = 0;
  const original = handle.instance.updateDirty;
  handle.instance.updateDirty = (...args: any[]) => { updates++; return original(...args); };
  try {
    window.dispatchEvent(new window.Event("cells-mixed"));
    await tick();
    expect(target.textContent).toBe("1 / 1");
    expect(updates).toBe(1);
    handle.destroy();
    modules["compiler-cells-state.mjs"].shared.count++;
    await tick();
    expect(updates).toBe(1);
    expect(target.textContent).toBe("");
  } finally {
    if (!handle.instance.destroyed) handle.destroy();
    window.close();
    (globalThis as any).window = previousWindow;
  }
}, 30000);

test("experimental component imports read live scalar bindings and retain lexical shadowing", async () => {
  const dir = mkdtempSync(join(tmpdir(), "weiv-cells-live-"));
  const path = join(dir, "Live.weiv");
  writeFileSync(path, `<template><p>{{ count }} / {{ read() }} / {{ own }}</p></template><script lang="ts">
    import {count} from './live-state.mjs';
    let own=0;
    function read(){return count}
    window.addEventListener('live-read', event=>{event.detail.value={count}; event.detail.shadow=((count)=>count)(99); own++;});
  </script>`);
  const previousWindow = (globalThis as any).window;
  let window: any, handle: any;
  try {
    const result = emit(path);
    if (result.exitCode) throw new Error(new TextDecoder().decode(result.stderr));
    const runtime = pathToFileURL(join(process.cwd(), "packages/weiv/src/runtime/cell.ts")).href;
    const code = new TextDecoder().decode(result.stdout).replace('"weiv:cells"', JSON.stringify(runtime));
    const modules = await loadModules({"Live.mjs":code,"live-state.mjs":"export let count=0; export function bump(){count++}"});
    const dom = installJsdom(); window = dom.window;
    (globalThis as any).window = window;
    const target = dom.document.createElement("div");
    handle = modules["Live.mjs"].mount(target, {});
    expect(target.textContent).toBe("0 / 0 / 0");
    modules["live-state.mjs"].bump();
    const detail: any = {};
    window.dispatchEvent(new window.CustomEvent("live-read", {detail}));
    expect(detail.value.count).toBe(1);
    expect(detail.shadow).toBe(99);
    await tick();
    const scope = handle.instance.refresh();
    expect(scope.count).toBe(1);
    expect(scope.read()).toBe(1);
    // The unmanaged scalar has no publisher yet. Supply its invalidation to
    // verify live reads independently of the pending shared-module bridge.
    handle.instance.updateDirty({bindings:["count", "read"], paths:[]}, scope);
    expect(target.textContent).toBe("1 / 1 / 1");
  } finally {
    handle?.destroy(); window?.close();
    (globalThis as any).window = previousWindow;
    rmSync(dir, {recursive:true,force:true});
  }
}, 30000);

test("standalone cells select helper/alias state and leave unrelated native declarations alone", async () => {
  const dir=mkdtempSync(join(tmpdir(),"weiv-cells-selection-"));
  const path=join(dir,"Select.weiv");
  writeFileSync(path,`<template><p>{{ read() }} / {{ retained === state }}</p></template><script lang="ts">
    const implementationCache=new Map(); let state={count:0}; const retained=state;
    function read(){return retained.count}
    window.addEventListener('cells-write',()=>state.count++);
  </script>`);
  let f: Awaited<ReturnType<typeof fixture>>|undefined;
  try {
    f=await fixture(path);const view=f.mount();
    expect(view.target.textContent).toBe("0 / true");
    f.send("cells-write");await tick();expect(view.target.textContent).toBe("1 / true");
  } finally {f?.close();rmSync(dir,{recursive:true,force:true});}
},30000);

test("snapshot callables subscribe to the local state their bodies read",async()=>{
  const dir=mkdtempSync(join(tmpdir(),"weiv-snapshot-callable-"));
  const path=join(dir,"Callable.weiv");
  writeFileSync(path,`<template><p>{{ captured.read() }}</p></template><script lang="ts">
    import {snapshot} from 'weiv:observable'; let count=0;
    const captured=snapshot({read:()=>count});
    window.addEventListener('cells-write',()=>count++);
  </script>`);
  let f:Awaited<ReturnType<typeof fixture>>|undefined;
  try {f=await fixture(path);const view=f.mount();expect(view.target.textContent).toBe("0");
    f.send("cells-write");await tick();expect(view.target.textContent).toBe("1");
  }finally{f?.close();rmSync(dir,{recursive:true,force:true});}
},30000);

test("helper-returned data preserves managed aliases and callable subscriptions",async()=>{
  const dir=mkdtempSync(join(tmpdir(),"weiv-returned-state-"));
  const path=join(dir,"Returned.weiv");
  writeFileSync(path,`<template><p>{{ view.item.count }} / {{ view.read() }} / {{ captured.count }}</p></template><script lang="ts">
    import {snapshot} from 'weiv:observable';
    const raw={count:0}; let count=0; const source={count:0};
    function make(){return {item:raw,read:()=>count}}
    function capture(){return snapshot(source)}
    const view=make(); const captured=capture();
    window.addEventListener('cells-write',()=>{raw.count++;count++;source.count++;});
  </script>`);
  let f:Awaited<ReturnType<typeof fixture>>|undefined;
  try {f=await fixture(path);const view=f.mount();expect(view.target.textContent).toBe("0 / 0 / 0");
    f.send("cells-write");await tick();expect(view.target.textContent).toBe("1 / 1 / 0");
    const code=new TextDecoder().decode(emit(path).stdout);
    expect(code).toContain('const source = {');
  }finally{f?.close();rmSync(dir,{recursive:true,force:true});}
},30000);

test("parameterized helper returns retain caller identities and captured subscriptions",async()=>{
  const dir=mkdtempSync(join(tmpdir(),"weiv-parameter-returns-"));
  const path=join(dir,"Parameters.weiv");
  writeFileSync(path,`<template><p>{{ direct.count }} / {{ forwarded.count }} / {{ callable.read() }} / {{ withDefault.count }}</p></template><script lang="ts">
    const raw={count:0};
    function identity(value){return value}
    function forward(value){return identity(value)}
    function make(value){return {read:()=>value.count}}
    function defaults(value={count:2}){return value}
    const direct=identity(raw);const forwarded=forward(raw);const callable=make(raw);const withDefault=defaults();
    window.addEventListener('cells-write',event=>{raw.count++;event.detail.same=direct===raw&&forwarded===raw;});
  </script>`);
  let f:Awaited<ReturnType<typeof fixture>>|undefined;
  try {f=await fixture(path);const view=f.mount();expect(view.target.textContent).toBe("0 / 0 / 0 / 2");
    const detail=f.send("cells-write");await tick();expect(detail.same).toBe(true);expect(view.target.textContent).toBe("1 / 1 / 1 / 2");
  }finally{f?.close();rmSync(dir,{recursive:true,force:true});}
},30000);

test("implicit primitive conversions subscribe to hook dependencies",async()=>{
  const dir=mkdtempSync(join(tmpdir(),"weiv-conversion-hooks-"));
  const path=join(dir,"Hooks.weiv");
  try {
    for(const [template,expected,locale] of [
      ['<p>{{ view }}</p>','1',false],
      ['<p>{{ view || "empty" }}</p>','1'],
      ['<p>{{ selected }}</p>','1'],
      ['<p>{{ view ?? "empty" }}</p>','1'],
      ['<p>{{ true ? view : "empty" }}</p>','1'],
      ['<p>{{ String(view) }}</p>','1'],
      ['<p>{{ view + 1 }}</p>','2'],
      ['<p>{{ rows.join() }}</p>','1'],
      ['<p>{{ rows.toLocaleString() }}</p>','1',true],
      ['<p :title="view">title</p>','title'],
    ]) {
      const initializer=locale?'{toString:()=>"fixed",toLocaleString:()=>String(count)}':'{toString:()=>String(count),valueOf:()=>count}';
      writeFileSync(path,'<template>'+template+'</template><script lang="ts">let count=0;const view='+initializer+';const rows=[view];const selected=view||"empty";window.addEventListener("cells-write",()=>count++);</script>');
      const f=await fixture(path);
      try {const view=f.mount();f.send("cells-write");await tick();expect(view.target.textContent).toBe(expected);
        if(expected==='title')expect(view.target.querySelector('p')?.getAttribute('title')).toBe('1');
      }finally{f.close();}
    }
  }finally{rmSync(dir,{recursive:true,force:true});}
},30000);

test("JSON hooks and converted helper results select their actual state sources",async()=>{
  const dir=mkdtempSync(join(tmpdir(),"weiv-native-protocols-"));const path=join(dir,"Protocols.weiv");
  try {
    for(const [template,script,expected] of [
      ['<p>{{ JSON.stringify(view) }}</p>','let count=0;const view={toJSON:()=>({count})};window.addEventListener("cells-write",()=>count++);','{"count":1}'],
      ['<p>{{ JSON.stringify(view) }}</p>','const view={count:0,toJSON(){return {count:this.count}}};window.addEventListener("cells-write",()=>view.count++);','{"count":1}'],
      ['<p>{{ JSON.stringify({child:view}) }}</p>','let count=0;const view={toJSON(key){return key?{count}:null}};window.addEventListener("cells-write",()=>count++);','{"child":{"count":1}}'],
      ['<p>{{ get() }}</p>','let count=0;const cache=new Map();function get(){return {toString:()=>String(count),unused:()=>cache.size}}window.addEventListener("cells-write",()=>count++);','1'],
      ['<p>{{ String(get()) }}</p>','let count=0;function get(){return {toString:()=>String(count)}}window.addEventListener("cells-write",()=>count++);','1'],
      ['<p>{{ Math.abs(get()) }}</p>','let count=0;function get(){return {valueOf:()=>count}}window.addEventListener("cells-write",()=>count++);','1'],
      ['<p>{{ JSON.stringify(get()) }}</p>','let count=0;function get(){return {toJSON:()=>({count})}}window.addEventListener("cells-write",()=>count++);','{"count":1}'],
      ['<p>{{ JSON.stringify({toJSON:()=>({count})}) }}</p>','let count=0;window.addEventListener("cells-write",()=>count++);','{"count":1}'],
      ['<p>{{ store.read() }}</p>','let count=0;const store={read(){return {toString:()=>String(count)}}};window.addEventListener("cells-write",()=>count++);','1'],
      ['<p>{{ JSON.stringify(store.read()) }}</p>','const store={count:0,read(){return {count:this.count}}};window.addEventListener("cells-write",()=>store.count++);','{"count":1}'],
      ['<p>{{ JSON.stringify(rows.map(({count:local})=>{const next=local+count;return {local,next};})) }}</p>','let count=0;const rows=[{count:4}];window.addEventListener("cells-write",()=>count++);','[{"local":4,"next":5}]'],
    ]) {
      writeFileSync(path,'<template>'+template+'</template><script lang="ts">'+script+'</script>');
      const f=await fixture(path);try {const view=f.mount();f.send("cells-write");await tick();expect(view.target.textContent).toBe(expected);}finally{f.close();}
    }
  }finally{rmSync(dir,{recursive:true,force:true});}
},30000);

test("native spread arguments retain conversion and serialization dependencies",async()=>{
  const dir=mkdtempSync(join(tmpdir(),"weiv-native-spread-"));const path=join(dir,"Spread.weiv");
  try {
    for(const [expression,declarations,expected] of [
      ['Math.max(...values)','const values=[{valueOf:()=>count}];','1'],
      ['Math.max(0,...values,2)','const values=[{valueOf:()=>count+2}];','3'],
      ['Math.pow(...values)','const values=[{valueOf:()=>count+2},2];','9'],
      ['Number(...values)','const values=[{valueOf:()=>count}];','1'],
      ['String(...values)','const values=[{toString:()=>String(count)}];','1'],
      ['JSON.stringify(...values)','const values=[{toJSON:()=>({count})}];','{"count":1}'],
      ['JSON.stringify(...[{toJSON:()=>({count})}])','const stringify=new Map();','{"count":1}'],
      ['JSON.stringify(...empty,view)','const empty=[];const view={toJSON:()=>({count})};','{"count":1}'],
      ['parseInt("10",radix)','const radix={valueOf:()=>count+2};','3'],
      ['parseInt(...values)','const values=["10",{valueOf:()=>count+2}];','3'],
      ['Object.hasOwn(...values)','const values=[{one:true},{toString:()=>count?"one":"zero"}];','true'],
      ['maximum(values)','const values=[{valueOf:()=>count}];function maximum(args){return Math.max(...args)}','1'],
      ['maximum(values)','const values=[{valueOf:()=>count}];const maximum=(args)=>{const forwarded=args;return Math.max(...forwarded)};','1'],
      ['Math.max(...argumentsFor(count))','function argumentsFor(value){return [value]}','1'],
      ['Math.max(...argumentsFor())','const cache=new Map();function argumentsFor(){return [{valueOf:()=>count,unused:()=>cache.size}]}','1'],
      ['JSON.stringify(...argumentsFor(view))','const view={toJSON:()=>({count})};function argumentsFor(value){const forwarded=value;return [forwarded]}','{"count":1}'],
      ['JSON.stringify(...argumentsFor(count))','function argumentsFor(value){return [{toJSON:()=>({value})}]}','{"value":1}'],
      ['Math.max(...argumentsFor(count))','function identity(value){return value}function argumentsFor(value){return identity([value])}','1'],
    ]) {
      writeFileSync(path,`<template><p>{{ ${expression} }}</p></template><script lang="ts">let count=0;${declarations}window.addEventListener('cells-write',()=>count++);</script>`);
      const f=await fixture(path);try {const view=f.mount();f.send("cells-write");await tick();expect(view.target.textContent).toBe(expected);}finally{f.close();}
    }
  }finally{rmSync(dir,{recursive:true,force:true});}
},30000);

test("supplied callbacks distinguish own arguments from captured outer state",async()=>{
  const dir=mkdtempSync(join(tmpdir(),"weiv-callback-ownership-"));const path=join(dir,"Callbacks.weiv");
  try {
    for(const [expression,declarations,mutation,expected] of [
      ['invoke(()=>count)','let count=0;function invoke(callback){return callback()}','count++','1'],
      ['invoke(value=>value.count,raw)','const raw={count:0};function invoke(callback,value){return callback(value)}','raw.count++','1'],
      ['invoke(({count})=>count,raw)','const raw={count:0};function invoke(callback,value){return callback(value)}','raw.count++','1'],
      ['invoke((...values)=>values[0].count,raw)','const raw={count:0};function invoke(callback,value){return callback(value)}','raw.count++','1'],
      ['invoke((value=raw)=>value.count)','const raw={count:0};function invoke(callback,value){return callback(value)}','raw.count++','1'],
      ['read()','let count=0;function read(){const step=()=>count;return step()}','count++','1'],
      ['invoke(callback,second)','const first={count:0};const second={count:0};function bind(value){return argument=>value.count+argument.count}const callback=bind(first);function invoke(callback,value){return callback(value)}','first.count++;second.count++','2'],
      ['invoke(make)','let count=0;const cache=new Map();function make(){return {toString:()=>String(count),unused:()=>cache.size}}function invoke(callback){return callback()}','count++','1'],
      ['JSON.stringify({child:invoke(callback,second)})','const first={count:0};const second={count:0};function bind(value){return argument=>({toJSON:key=>({first:value.count,second:argument.count,key:key?"child":"root"})})}const callback=bind(first);function invoke(callback,value){return callback(value)}','first.count++;second.count++','{"child":{"first":1,"second":1,"key":"child"}}'],
    ]) {
      writeFileSync(path,`<template><p>{{ ${expression} }}</p></template><script lang="ts">${declarations}window.addEventListener('cells-write',()=>{${mutation}});</script>`);
      const f=await fixture(path);try {const view=f.mount();f.send("cells-write");await tick();expect(view.target.textContent).toBe(expected);}finally{f.close();}
    }
  }finally{rmSync(dir,{recursive:true,force:true});}
},30000);

test("callback ownership observes captured and argument values independently",async()=>{
  const dir=mkdtempSync(join(tmpdir(),"weiv-independent-callbacks-"));const path=join(dir,"Independent.weiv");
  writeFileSync(path,`<template><p>{{ invoke(callback,second) }}</p></template><script lang="ts">
    const first={count:0};const second={count:10};
    function bind(value){return argument=>value.count+argument.count}
    const callback=bind(first);function invoke(callback,value){return callback(value)}
    window.addEventListener('first-write',()=>first.count++);
    window.addEventListener('second-write',()=>second.count++);
  </script>`);
  try {const f=await fixture(path);try {const view=f.mount();expect(view.target.textContent).toBe('10');
    f.send('first-write');await tick();expect(view.target.textContent).toBe('11');
    f.send('second-write');await tick();expect(view.target.textContent).toBe('12');
  }finally{f.close();}}finally{rmSync(dir,{recursive:true,force:true});}
},30000);

test("callback methods preserve receivers and proven computed keys",async()=>{
  const dir=mkdtempSync(join(tmpdir(),"weiv-method-callbacks-"));const path=join(dir,"Methods.weiv");
  try {
    for(const [expression,declarations,mutation,expected] of [
      ['invoke(holder)','const holder={count:0,read(){return this.count}};function invoke(value){return value.read()}','holder.count++','1'],
      ['invoke(holder,"read")','const cache=new Map();const holder={count:0,read(){return this.count},unused:()=>cache.size};function invoke(value,key){return value[key]()}','holder.count++','1'],
      ['invoke(holder)','const holder={count:0,read(){return this.count}};function invoke(value){const key="read";return value[key]()}','holder.count++','1'],
      ['invoke(holder,"child")','const holder={child:{count:0,read(){return this.count}}};function invoke(value,key){return value[key].read()}','holder.child.count++','1'],
      ['invoke(holder)','let count=0;const holder={count:100,read:()=>count};function invoke(value){return value["read"]()}','count++','1'],
      ['JSON.stringify(invoke(holder,raw))','const holder={count:0,read(value){return {toJSON:()=>({own:this.count,argument:value.count})}}};const raw={count:10};function invoke(value,argument){return value.read(argument)}','holder.count++;raw.count++','{"own":1,"argument":11}'],
    ]) {
      writeFileSync(path,`<template><p>{{ ${expression} }}</p></template><script lang="ts">${declarations}window.addEventListener('cells-write',()=>{${mutation}});</script>`);
      const f=await fixture(path);try {const view=f.mount();f.send("cells-write");await tick();expect(view.target.textContent).toBe(expected);}finally{f.close();}
    }
  }finally{rmSync(dir,{recursive:true,force:true});}
},30000);

test("callback-produced spread arrays retain scopes through argument consumption",async()=>{
  const dir=mkdtempSync(join(tmpdir(),"weiv-callback-iterables-"));const path=join(dir,"Iterables.weiv");
  try {
    for(const [expression,declarations,mutation,expected] of [
      ['Math.max(...invoke(()=>[count]))','let count=0;function invoke(callback){return callback()}','count++','1'],
      ['JSON.stringify(...invoke(value=>[{toJSON:()=>({count:value.count})}],raw))','const raw={count:0};function invoke(callback,value){return callback(value)}','raw.count++','{"count":1}'],
      ['Math.max(...invoke(holder,"read"))','let count=0;const holder={read(){return [count]}};function invoke(value,key){return value[key]()}','count++','1'],
      ['Math.max(...invoke(holder,"read"))','const holder={count:0,read(){return [this.count]}};function invoke(value,key){return value[key]()}','holder.count++','1'],
      ['Math.max(...invoke(holder,"read"))','const holder={count:0,read(){return [{valueOf:()=>this.count}]}};function invoke(value,key){return value[key]()}','holder.count++','1'],
      ['Math.max(...invoke(callback,raw))','const raw={count:0};function bind(offset){return value=>[value.count+offset]}const callback=bind(10);function invoke(callback,value){return callback(value)}','raw.count++','11'],
      ['Math.max(...invoke(value=>[value.count],raw))','const raw={count:0};function invoke(callback,value){callback({count:100});return callback(value)}','raw.count++','1'],
    ]) {
      writeFileSync(path,`<template><p>{{ ${expression} }}</p></template><script lang="ts">${declarations}window.addEventListener('cells-write',()=>{${mutation}});</script>`);
      const f=await fixture(path);try {const view=f.mount();f.send("cells-write");await tick();expect(view.target.textContent).toBe(expected);}finally{f.close();}
    }
  }finally{rmSync(dir,{recursive:true,force:true});}
},30000);

test("managed data aliases normalize before entering plain and explicit observable containers",async()=>{
  const dir=mkdtempSync(join(tmpdir(),"weiv-owned-aliases-"));
  const path=join(dir,"Aliases.weiv");
  try {
    for(const [initializer,render,alias] of [
      ["observable(raw)","wrapped.count","wrapped"],
      ["{child:raw}","wrapped.child.count","wrapped.child"],
      ["[raw]","wrapped.map(item=>item.count).join(',')","wrapped[0]"],
    ]){
      writeFileSync(path,`<template><p>{{ ${render} }}</p></template><script lang="ts">
        import {observable} from 'weiv:observable'; const raw={count:0}; const wrapped=${initializer};
        window.addEventListener('cells-write',event=>{raw.count++;event.detail.same=raw===${alias};});
      </script>`);
      const f=await fixture(path);
      try {const view=f.mount();expect(view.target.textContent).toBe("0");
        expect(f.send("cells-write").same).toBe(true);await tick();expect(view.target.textContent).toBe("1");
      }finally{f.close();}
    }
  }finally{rmSync(dir,{recursive:true,force:true});}
},30000);


test("experimental compiler keeps explicit snapshots immutable until recaptured", async () => {
  const f = await fixture("test/examples/basic/compiler-cells-snapshot.weiv");
  try {
    const view = f.mount();
    expect(view.text(".captured")).toBe("1");
    f.send("snapshot-source");
    await tick();
    expect(view.text(".captured")).toBe("1");
    f.send("snapshot-capture");
    await tick();
    expect(view.text(".captured")).toBe("2");
  } finally { f.close(); }
}, 30000);


test("experimental object assignment results retain tracked identity and short circuiting", async () => {
  const f = await fixture();
  try {
    const view = f.mount();
    const detail = f.send("cells-return");
    await tick();
    expect(detail.same).toBe(true);
    expect(detail.optionalSame).toBe(true);
    expect(detail.skipped).toBe(true);
    expect(detail.calls).toBe(0);
    expect(view.text(".object")).toBe("21");
  } finally { f.close(); }
}, 30000);
