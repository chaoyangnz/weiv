import {expect,test} from 'bun:test';
import {observable,subscribe,snapshot,isObservable} from '../../packages/weiv/src/runtime/observable';
import {createCell,createCellScope} from '../../packages/weiv/src/runtime/cell';
const tick=()=>new Promise<void>(resolve=>queueMicrotask(resolve));

test('array length keeps native coercion and detaches children inserted during conversion',async()=>{
  const child=observable({count:0});const items=observable([{count:0}]);
  let coercions=0,calls=0;const stop=subscribe(items,()=>calls++);
  const length={valueOf(){coercions++;items.push(child);return 0}};
  expect(Reflect.defineProperty(items,'length',{value:length})).toBe(true);
  expect(coercions).toBe(2);expect(items.length).toBe(0);
  await tick();expect(calls).toBe(1);
  child.count++;await tick();expect(calls).toBe(1);
  items.push({count:0},{count:0});await tick();
  Reflect.defineProperty(items,'length',{value:new Number(1)});
  await tick();expect(items.length).toBe(1);
  const previous=calls;
  expect(()=>Reflect.defineProperty(items,'length',{value:1n})).toThrow(TypeError);
  await tick();expect(calls).toBe(previous);expect(items.length).toBe(1);
  stop();
});

test('symbol-owned children notify and detach without conflating symbol identities',async()=>{
  const first=Symbol('child'),second=Symbol('child');
  const child=observable({count:0});
  const state=observable({[first]:child,[second]:child});
  let calls=0,paths:ReadonlySet<string>|null=new Set();
  const stop=subscribe(state,next=>{calls++;paths=next});
  const retained=state[first];
  retained.count++;await tick();expect(calls).toBe(1);expect(paths).toBe(null);
  delete (state as any)[first];await tick();
  retained.count++;await tick();expect(calls).toBe(3);
  delete (state as any)[second];await tick();
  retained.count++;await tick();expect(calls).toBe(4);
  stop();
});

test('array truncation detaches removed children while retaining other aliases',async()=>{
  const child=observable({count:0});
  const state=observable({items:[child],other:child});
  const retained=state.items[0];
  let calls=0;const stop=subscribe(state,()=>calls++);
  state.items.length=0;await tick();expect(calls).toBe(1);
  retained.count++;await tick();expect(calls).toBe(2);
  delete (state as any).other;await tick();expect(calls).toBe(3);
  retained.count++;await tick();expect(calls).toBe(3);
  stop();
});

test('failed array length reduction publishes its successful suffix deletion',async()=>{
  const raw=[{count:0},{count:0},{count:0}];
  Object.defineProperty(raw,'1',{configurable:false});
  const state=observable(raw);
  const removed=state[2],retained=state[1];
  const changes:Array<ReadonlySet<string>|null>=[];
  const stop=subscribe(state,paths=>changes.push(paths));
  expect(Reflect.defineProperty(state,'length',{value:0})).toBe(false);
  expect(state.length).toBe(2);expect(2 in state).toBe(false);
  await tick();expect(changes).toHaveLength(1);expect(changes[0]?.has('length')).toBe(true);expect(changes[0]?.has('2')).toBe(true);
  removed.count++;await tick();expect(changes).toHaveLength(1);
  retained.count++;await tick();expect(changes).toHaveLength(2);
  stop();
});

test('reflective data writes preserve aliases and notify structural descriptor changes',async()=>{
  const state=observable({child:{count:0},other:0});
  const old=state.child;
  let calls=0;const stop=subscribe(state,()=>calls++);
  const child=observable({count:10});
  Object.defineProperty(state,'child',{value:child});
  expect(state.child).toBe(child);
  const alias=Object.getOwnPropertyDescriptor(state,'child')!.value;
  expect(alias).toBe(child);expect(isObservable(alias)).toBe(true);
  alias.count++;await tick();expect(calls).toBe(1);
  old.count++;await tick();expect(calls).toBe(1);
  Object.defineProperty(state,'child',{enumerable:false});await tick();expect(calls).toBe(2);expect(Object.keys(state)).toEqual(['other']);
  Object.defineProperty(state,'child',{enumerable:false});await tick();expect(calls).toBe(2);
  stop();
});

test('unsupported descriptors and immutability fail before changing tracked state',async()=>{
  const state=observable({child:{count:0}});
  expect(()=>observable(new (class Collection extends Array {})())).toThrow(TypeError);
  let calls=0;const stop=subscribe(state,()=>calls++);
  const child=state.child;
  for(const descriptor of [{value:new Map()},{get(){return 0}},{writable:false}]){
    expect(()=>Object.defineProperty(state,'child',descriptor)).toThrow(TypeError);
    expect(state.child).toBe(child);
  }
  expect(()=>Object.defineProperty(state,'new',{value:1})).toThrow('writable data properties');
  expect(Object.hasOwn(state,'new')).toBe(false);
  for(const operation of [Object.freeze,Object.seal,Object.preventExtensions])expect(()=>operation(state)).toThrow('snapshot()');
  expect(Object.isExtensible(state)).toBe(true);
  expect(()=>Object.setPrototypeOf(state,new Map())).toThrow('plain object and array prototypes');
  await tick();expect(calls).toBe(0);
  state.child.count++;await tick();expect(calls).toBe(1);
  stop();
});

test('Reflect.set respects other receivers without dirtying or unwrapping into them',async()=>{
  const state=observable({child:{count:0}});
  const receiver:any={};const child=observable({count:10});
  let calls=0;const stop=subscribe(state,()=>calls++);
  expect(Reflect.set(state,'child',child,receiver)).toBe(true);
  expect(receiver.child).toBe(child);expect(state.child.count).toBe(0);
  expect(Reflect.set(state,'child',new Date(0),receiver)).toBe(true);expect(receiver.child).toBeInstanceOf(Date);
  await tick();expect(calls).toBe(0);
  stop();
});

test('same shared value assignments are silent even when initially stored as a proxy',async()=>{
  const shared=observable({count:0});const cell=createCell(shared);
  let calls=0;const scope=createCellScope(()=>calls++);scope.watch(cell,'value');
  cell.value=shared;await tick();expect(calls).toBe(0);
  shared.count++;await tick();expect(calls).toBe(1);
  scope.dispose();
});

test('plain prototype changes invalidate and inherited deletes remain silent',async()=>{
  const state=observable({count:0});let calls=0;
  const stop=subscribe(state,()=>calls++);
  delete (state as any).toString;await tick();expect(calls).toBe(0);
  Object.setPrototypeOf(state,null);await tick();expect(calls).toBe(1);expect(Object.getPrototypeOf(state)).toBe(null);
  Object.setPrototypeOf(state,null);await tick();expect(calls).toBe(1);
  stop();
});

test('snapshots retain sparse array lengths and own __proto__ data without changing prototypes',()=>{
  const array=new Array(4);array[1]={count:0};
  const raw=Object.create(null);Object.defineProperty(raw,'__proto__',{value:{count:1},enumerable:true,writable:true});raw.items=array;
  const captured=snapshot(observable(raw));
  expect(Object.getPrototypeOf(captured)).toBe(null);
  expect(Object.hasOwn(captured,'__proto__')).toBe(true);expect(captured.__proto__.count).toBe(1);
  expect(captured.items.length).toBe(4);expect(0 in captured.items).toBe(false);expect(2 in captured.items).toBe(false);
  expect(Object.isFrozen(captured.items)).toBe(true);
});
