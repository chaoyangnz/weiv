import { reactiveScheduler, sharedRuntime } from "./reactive-core.ts";

type Listener = (paths: ReadonlySet<string> | null) => void;

const WEIV_OBSERVABLE = Symbol.for("weiv.observable");

type RootState = {
  pending: Map<NodeState, Set<string> | null>;
};

type NodeState = {
  root: RootState;
  target: object;
  proxy: object;
  listeners: Set<Listener>;
  parents: Map<WeakRef<NodeState>, Set<PropertyKey>>;
  parentRefs: WeakMap<NodeState, WeakRef<NodeState>>;
};

const { rawToNode, proxyToNode, snapshots } = sharedRuntime("weiv.reactivity.observable.v1", () => ({
  rawToNode: new WeakMap<object, NodeState>(),
  proxyToNode: new WeakMap<object, NodeState>(),
  // Explicit snapshots are immutable inputs, not new mutable observable roots.
  snapshots: new WeakSet<object>(),
}));

function isObject(value: unknown): value is object {
  return typeof value === "object" && value !== null;
}

function validateObservableValue(value: unknown, seen = new WeakSet<object>()) {
  if (!isObject(value) || snapshots.has(value) || seen.has(value) || rawToNode.has(value) || proxyToNode.has(value)) return;
  getObservableNode(value); // Reject incompatible metadata before mutating a graph.
  seen.add(value);
  const prototype = Object.getPrototypeOf(value);
  if (prototype !== Object.prototype && prototype !== null && !(Array.isArray(value) && prototype === Array.prototype)) {
    throw new TypeError("Weiv observable state supports only plain objects and arrays; adapt native or class values into plain data");
  }
  if (!Object.isExtensible(value)) {
    throw new TypeError("Weiv observable state requires extensible objects and arrays");
  }
  for (const key of Reflect.ownKeys(value)) {
    const descriptor = Reflect.getOwnPropertyDescriptor(value, key)!;
    if (!("value" in descriptor) || !descriptor.writable) {
      throw new TypeError("Weiv observable state requires writable data properties; accessors and read-only properties are unsupported");
    }
    validateObservableValue(descriptor.value, seen);
  }
}

function defineObservableBrand(target: object, node: NodeState) {
  Object.defineProperty(target, WEIV_OBSERVABLE, {
    value: node,
    enumerable: false,
    configurable: false,
    writable: false,
  });
}

function getObservableNode(value: unknown): NodeState | undefined {
  if (!isObject(value)) return undefined;
  const direct = proxyToNode.get(value) ?? rawToNode.get(value);
  if (direct) return direct;
  if (Reflect.get(value, WEIV_OBSERVABLE) != null) {
    throw new TypeError("Incompatible Weiv observable runtime or realm; use one compatible runtime or snapshot() to transfer read-only data");
  }
  return undefined;
}

function unwrapValue<T>(value: T): T {
  if (!isObject(value)) return value;
  const node = getObservableNode(value);
  return (node?.target ?? value) as T;
}

function scheduleFlush(root: RootState) {
  reactiveScheduler.notify(root, () => {
    const notifying = Array.from(root.pending, ([node, paths]) => ({
      node, paths, listeners: Array.from(node.listeners),
    }));
    root.pending.clear();
    return () => {
      const errors: unknown[] = [];
      for (const { node, paths, listeners } of notifying) {
        for (const listener of listeners) {
          if (!node.listeners.has(listener)) continue;
          try { listener(paths); } catch (error) { errors.push(error); }
        }
      }
      if (errors.length) throw new AggregateError(errors, "Weiv observable subscribers failed");
    };
  });
}

function linkParent(child: NodeState, parent: NodeState, key: PropertyKey) {
  let reference = child.parentRefs.get(parent);
  if (!reference) {
    reference = new WeakRef(parent);
    child.parentRefs.set(parent, reference);
  }
  let keys = child.parents.get(reference);
  if (!keys) child.parents.set(reference, (keys = new Set()));
  keys.add(key);
}

function unlinkParent(child: NodeState, parent: NodeState, key: PropertyKey) {
  const reference = child.parentRefs.get(parent);
  if (!reference) return;
  const keys = child.parents.get(reference);
  keys?.delete(key);
  if (keys?.size === 0) {
    child.parents.delete(reference);
    child.parentRefs.delete(parent);
  }
}

function unlinkRemovedChildren(previous: unknown, next: unknown, parent: NodeState, key: PropertyKey) {
  if (!isObject(previous)) return;
  if (Object.is(unwrapValue(previous), unwrapValue(next))) return;

  const previousNode = rawToNode.get(previous) ?? proxyToNode.get(previous);
  if (!previousNode) return;

  unlinkParent(previousNode, parent, key);
}

function markChanged(node: NodeState, key: PropertyKey) {
  const touchedRoots = new Set<RootState>();
  const queue: Array<{ node: NodeState; path: string | null; ancestors: Set<NodeState> }> = [
    { node, path: typeof key === "symbol" ? null : String(key), ancestors: new Set([node]) },
  ];
  while (queue.length > 0) {
    const current = queue.pop()!;
    const pending = current.node.root.pending;
    touchedRoots.add(current.node.root);
    const existing = pending.get(current.node);
    if (!pending.has(current.node)) {
      pending.set(current.node, current.path === null ? null : new Set([current.path]));
    } else if (current.path === null) {
      pending.set(current.node, null);
    } else {
      existing?.add(current.path);
    }
    for (const [reference, keys] of current.node.parents) {
      const parent = reference.deref();
      if (!parent) {
        current.node.parents.delete(reference);
        continue;
      }
      if (current.ancestors.has(parent)) {
        parent.root.pending.set(parent, null);
        touchedRoots.add(parent.root);
        continue;
      }
      for (const parentKey of keys) {
        queue.push({
          node: parent,
          path: current.path === null || typeof parentKey === "symbol" ? null : `${parentKey}.${current.path}`,
          ancestors: new Set([...current.ancestors, parent]),
        });
      }
    }
  }

  for (const root of touchedRoots) scheduleFlush(root);
}

function ensureObservableNode(target: object, root: RootState, parent: NodeState | null, key?: PropertyKey): NodeState {
  const existing = rawToNode.get(target) ?? proxyToNode.get(target);
  if (existing) {
    if (parent && key !== undefined) linkParent(existing, parent, key);
    return existing;
  }

  const node: NodeState = {
    root,
    target,
    proxy: undefined as unknown as object,
    listeners: new Set(),
    parents: new Map(),
    parentRefs: new WeakMap(),
  };
  if (parent && key !== undefined) linkParent(node, parent, key);

  const proxy = new Proxy(target, {
    get(currentTarget, prop, receiver) {
      const value = Reflect.get(currentTarget, prop, receiver);
      if (prop === WEIV_OBSERVABLE) return value;
      if (!isObject(value) || snapshots.has(value)) return value;
      return ensureObservableNode(value, root, node, prop).proxy;
    },

    set(currentTarget, prop, value, receiver) {
      // Ordinary receiver semantics delegate a write back through defineProperty
      // when this proxy receives it. Another receiver must keep its own identity
      // and validation rules, and must not dirty this target.
      return Reflect.set(currentTarget, prop, value, receiver);
    },

    getOwnPropertyDescriptor(currentTarget, prop) {
      const descriptor = Reflect.getOwnPropertyDescriptor(currentTarget, prop);
      if (descriptor && prop !== WEIV_OBSERVABLE && isObject(descriptor.value) && !snapshots.has(descriptor.value)) {
        descriptor.value = ensureObservableNode(descriptor.value, root, node, prop).proxy;
      }
      return descriptor;
    },

    defineProperty(currentTarget, prop, descriptor) {
      const previous = Reflect.getOwnPropertyDescriptor(currentTarget, prop);
      if ("get" in descriptor || "set" in descriptor || !(descriptor.writable ?? previous?.writable ?? false)) {
        throw new TypeError("Weiv observable state requires writable data properties; use snapshot() for immutable views");
      }
      const normalized = { ...descriptor };
      if ("value" in descriptor) {
        if (Array.isArray(currentTarget) && prop === "length") {
          // Length stores a number, not the coercion input. Let the engine
          // perform its native conversions before capturing removed children:
          // valueOf may itself insert new children that must later detach.
          if (typeof descriptor.value !== "number") {
            const length = [];
            Reflect.defineProperty(length, "length", { value: descriptor.value });
            normalized.value = length.length;
          }
        } else {
          normalized.value = unwrapValue(descriptor.value);
          validateObservableValue(normalized.value);
        }
      }
      const oldLength = Array.isArray(currentTarget) ? currentTarget.length : undefined;
      // Length reduction can remove many child edges, including non-enumerable
      // indices. A failed reduction may still delete a suffix before hitting a
      // non-configurable index, so inspect the actual result in finally.
      const truncating = oldLength !== undefined && prop === "length" && "value" in descriptor &&
        !(typeof normalized.value === "number" && normalized.value >= oldLength);
      const indices = truncating ? Reflect.ownKeys(currentTarget).filter(isArrayIndex).map(key =>
        [key, Reflect.getOwnPropertyDescriptor(currentTarget, key)!.value] as const) : [];
      try {
        return Reflect.defineProperty(currentTarget, prop, normalized);
      } finally {
        const actual = Reflect.getOwnPropertyDescriptor(currentTarget, prop);
        const next = actual?.value;
        unlinkRemovedChildren(previous?.value, next, node, prop);
        if (isObject(next) && !snapshots.has(next)) ensureObservableNode(next, root, node, prop);
        const changed = previous === undefined ? actual !== undefined : actual === undefined ||
          !Object.is(unwrapValue(previous.value), unwrapValue(next)) || previous.enumerable !== actual.enumerable ||
          previous.configurable !== actual.configurable || previous.writable !== actual.writable;
        if (changed) markChanged(node, prop);
        for (const [key, child] of indices) {
          if (Reflect.getOwnPropertyDescriptor(currentTarget, key)) continue;
          unlinkRemovedChildren(child, undefined, node, key);
          markChanged(node, key);
        }
        if (Array.isArray(currentTarget) && currentTarget.length !== oldLength && prop !== "length") markChanged(node, "length");
      }
    },

    deleteProperty(currentTarget, prop) {
      const previous = Reflect.getOwnPropertyDescriptor(currentTarget, prop);
      const updated = Reflect.deleteProperty(currentTarget, prop);
      if (updated && previous) {
        unlinkRemovedChildren(previous.value, undefined, node, prop);
        markChanged(node, prop);
        if (Array.isArray(currentTarget) && prop !== "length") markChanged(node, "length");
      }
      return updated;
    },

    setPrototypeOf(currentTarget, prototype) {
      if (prototype !== null && prototype !== Object.prototype && !(Array.isArray(currentTarget) && prototype === Array.prototype)) {
        throw new TypeError("Weiv observable state supports only plain object and array prototypes");
      }
      if (Reflect.getPrototypeOf(currentTarget) === prototype) return true;
      const updated = Reflect.setPrototypeOf(currentTarget, prototype);
      if (updated) markChanged(node, WEIV_OBSERVABLE); // Unknown property path.
      return updated;
    },

    preventExtensions() {
      throw new TypeError("Weiv observable state must remain extensible; use snapshot() for an immutable view");
    },
  });

  node.proxy = proxy;
  defineObservableBrand(target, node);
  rawToNode.set(target, node);
  proxyToNode.set(proxy, node);
  // An already-observable child can be mutated through another owner before
  // this parent is ever read. Register every initial edge, including cycles,
  // before publishing the graph; lazy getters alone would lose that change.
  for (const childKey of Reflect.ownKeys(target)) {
    if (childKey === WEIV_OBSERVABLE) continue;
    const child = Reflect.getOwnPropertyDescriptor(target, childKey)?.value;
    if (isObject(child) && !snapshots.has(child)) ensureObservableNode(child, root, node, childKey);
  }
  return node;
}

function isArrayIndex(key: PropertyKey): key is string {
  if (typeof key !== "string") return false;
  const index = Number(key);
  return Number.isInteger(index) && index >= 0 && index < 0xffffffff && String(index) === key;
}

export function observable<T extends object>(value: T): T {
  if (isObject(value) && snapshots.has(value)) throw new TypeError("observable() cannot make an explicit snapshot mutable; store it as a read-only cell value instead");
  if (!isObject(value)) throw new TypeError("observable() expects a plain object or array");
  const existing = getObservableNode(value);
  if (existing) {
    return existing.proxy as T;
  }

  validateObservableValue(value);

  const root: RootState = {
    pending: new Map(),
  };

  return ensureObservableNode(value, root, null).proxy as T;
}

export function subscribe<T extends object>(value: T, listener: Listener): () => void {
  const node = getObservableNode(value);
  if (!node) {
    throw new Error("subscribe() expects a value created by observable()");
  }
  // Each subscription has its own identity. A disposed registration must not
  // become live again in a captured wave when the same callback resubscribes.
  const registration: Listener = paths => listener(paths);
  node.listeners.add(registration);
  return () => {
    node.listeners.delete(registration);
  };
}

export function snapshot<T>(value: T): T {
  const seen = new WeakMap<object, object>();

  function clone(current: unknown): unknown {
    if (!isObject(current)) return current;

    // A snapshot is the explicit data-transfer adapter. It may read a foreign
    // proxy's enumerable data without trusting that runtime's private metadata.
    const node = proxyToNode.get(current) ?? rawToNode.get(current);
    const source = node?.target ?? current;

    const existing = seen.get(source);
    if (existing) return existing;

    const out: Record<string | symbol, unknown> | unknown[] = Array.isArray(source)
      ? new Array(source.length) : Object.create(Object.getPrototypeOf(source) === null ? null : Object.prototype);
    seen.set(source, out);

    for (const key of Reflect.ownKeys(source)) {
      if (key === WEIV_OBSERVABLE) continue;
      const descriptor = Reflect.getOwnPropertyDescriptor(source, key);
      if (!descriptor || !descriptor.enumerable) continue;
      Object.defineProperty(out, key, { value: clone(Reflect.get(source, key)), enumerable: true, writable: true, configurable: true });
    }

    snapshots.add(out);
    return Object.freeze(out);
  }

  return clone(value) as T;
}

export function isObservable(value: unknown): boolean {
  return isObject(value) && (proxyToNode.has(value) || rawToNode.has(value));
}

export function observableBrandSymbol(): symbol {
  return WEIV_OBSERVABLE;
}
