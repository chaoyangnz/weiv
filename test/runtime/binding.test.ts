import {expect, test} from "bun:test";
import {bindingObject, bindingIterator} from "../../packages/weiv/src/runtime/binding";

test("declaration object extraction converts keys once and copies rest in native order",()=>{
  const trace:string[]=[];const slot=Symbol('slot');
  const source=new Proxy({a:1,b:2,[slot]:3}, {
    ownKeys(target){trace.push('keys');return Reflect.ownKeys(target)},
    getOwnPropertyDescriptor(target,key){trace.push('descriptor-'+String(key));return Reflect.getOwnPropertyDescriptor(target,key)},
    get(target,key,receiver){trace.push('get-'+String(key));return Reflect.get(target,key,receiver)},
  });
  const key={[Symbol.toPrimitive](hint:string){trace.push('key-'+hint);return slot}};
  const object=bindingObject(source);expect(object.get(key)).toBe(3);expect(object.rest()).toEqual({a:1,b:2});
  expect(trace).toEqual(['key-string','get-Symbol(slot)','keys','descriptor-a','get-a','descriptor-b','get-b']);
});

test("declaration object extraction keeps primitive receivers and own __proto__ data",()=>{
  const symbol=Symbol('receiver');
  Object.defineProperty(Number.prototype,symbol,{get:function(){'use strict';return typeof this},configurable:true});
  try{expect(bindingObject(1).get(symbol)).toBe('number')}finally{delete (Number.prototype as any)[symbol]}
  const input=Object.create(null);input.__proto__={count:1};
  const rest=bindingObject(input).rest();expect(Object.getPrototypeOf(rest)).toBe(Object.prototype);
  expect(Object.hasOwn(rest,'__proto__')).toBe(true);expect((rest as any).__proto__).toBe(input.__proto__);
  expect(()=>bindingObject(null)).toThrow(TypeError);
});

test("declaration iterator holes avoid value access and close uses the original iterator",()=>{
  const trace:string[]=[];
  const iterator={next(){trace.push(this===iterator?'next':'wrong');return {done:false,get value(){trace.push('value');return 4}}},return(){trace.push(this===iterator?'return':'wrong');return {}}};
  const input={[Symbol.iterator](){return iterator}};
  const cursor=bindingIterator(input);cursor.skip();expect(cursor.step()).toBe(4);cursor.close(false);cursor.close(false);
  expect(trace).toEqual(['next','next','value','return']);
});

test("declaration iterator abrupt steps and cleanup preserve exception precedence",()=>{
  let closes=0;
  const input={[Symbol.iterator](){return {next(){return {done:false,get value(){throw Error('value')}}},return(){closes++;throw Error('close')}}}};
  const cursor=bindingIterator(input);expect(()=>cursor.step()).toThrow('value');cursor.close(true);expect(closes).toBe(0);
  const source={[Symbol.iterator](){return {next(){return {done:false,value:undefined}},return(){closes++;throw Error('close')}}}};
  const abrupt=bindingIterator(source);abrupt.step();expect(()=>abrupt.close(true)).not.toThrow();expect(closes).toBe(1);
  const normal=bindingIterator(source);normal.step();expect(()=>normal.close(false)).toThrow('close');expect(closes).toBe(2);
});
