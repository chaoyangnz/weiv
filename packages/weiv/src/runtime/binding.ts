// Internal declaration lowering. Native outer bindings initialize between
// generator yields; these helpers implement extraction and IteratorClose only.
function objectLike(value: unknown): value is object {
  return value !== null && (typeof value === "object" || typeof value === "function");
}

export function bindingObject(source: any) {
  if (source == null) throw new TypeError("Cannot destructure null or undefined");
  const object = Object(source);
  const excluded = new Set<PropertyKey>();
  return {
    get(input: any) {
      // Computed property syntax performs ToPropertyKey, including symbol-valued
      // conversion hooks, exactly once. String(input) has different semantics.
      const key = Reflect.ownKeys({ [input]: 0 })[0];
      excluded.add(key);
      return Reflect.get(object, key, source);
    },
    rest() {
      const result = {};
      for (const key of Reflect.ownKeys(object)) {
        if (excluded.has(key)) continue;
        if (!Reflect.getOwnPropertyDescriptor(object, key)?.enumerable) continue;
        Reflect.defineProperty(result, key, {
          value: Reflect.get(object, key),
          enumerable: true,
          writable: true,
          configurable: true,
        });
      }
      return result;
    },
  };
}

export function bindingIterator(source: any) {
  const method = source[Symbol.iterator];
  const iterator = Reflect.apply(method, source, []);
  if (!objectLike(iterator)) throw new TypeError("Iterator must return an object");
  const next = (iterator as any).next;
  let done = false;
  const step = (read: boolean) => {
    if (done) return undefined;
    try {
      const result = Reflect.apply(next, iterator, []);
      if (!objectLike(result)) throw new TypeError("Iterator result must be an object");
      if ((result as any).done) {
        done = true;
        return undefined;
      }
      return read ? (result as any).value : undefined;
    } catch (error) {
      // An abrupt IteratorStepValue marks the iterator done. Defaults and nested
      // binding failures happen after step() and still require IteratorClose.
      done = true;
      throw error;
    }
  };
  return {
    step: () => step(true),
    skip: () => {
      step(false);
    },
    rest() {
      const result: unknown[] = [];
      while (!done) {
        const value = step(true);
        if (!done)
          Reflect.defineProperty(result, String(result.length), {
            value,
            enumerable: true,
            writable: true,
            configurable: true,
          });
      }
      return result;
    },
    close(abrupt: boolean) {
      if (done) return;
      done = true;
      try {
        const finish = (iterator as any).return;
        if (finish == null) return;
        const result = Reflect.apply(finish, iterator, []);
        if (!objectLike(result)) throw new TypeError("Iterator return must return an object");
      } catch (error) {
        if (!abrupt) throw error;
      }
    },
  };
}
