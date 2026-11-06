const std = @import("std");

pub fn emitPrelude(out: *std.ArrayList(u8), allocator: std.mem.Allocator) !void {
    try out.appendSlice(allocator,
        \\function replaceBetween(start, end, content) {
        \\  const parent = start.parentNode;
        \\  if (!parent || parent !== end.parentNode) {
        \\    throw new Error("Conditional boundary is detached");
        \\  }
        \\  let current = start.nextSibling;
        \\  while (current && current !== end) {
        \\    const next = current.nextSibling;
        \\    parent.removeChild(current);
        \\    current = next;
        \\  }
        \\  parent.insertBefore(content, end);
        \\}
        \\
        \\function moveBoundaryBefore(start, end, reference) {
        \\  const parent = reference.parentNode;
        \\  if (!parent || parent !== start.parentNode || parent !== end.parentNode) {
        \\    throw new Error("Boundary move target is detached");
        \\  }
        \\  const nodes = [];
        \\  let current = start;
        \\  while (current) {
        \\    nodes.push(current);
        \\    if (current === end) break;
        \\    current = current.nextSibling;
        \\  }
        \\  for (const node of nodes) {
        \\    parent.insertBefore(node, reference);
        \\  }
        \\}
        \\
        \\function cloneScope(scope) {
        \\  const snapshot = {};
        \\  for (const key of Object.keys(scope)) {
        \\    snapshot[key] = scope[key];
        \\  }
        \\  return snapshot;
        \\}
        \\
        \\function hasScopeChanged(beforeScope, afterScope) {
        \\  const beforeKeys = Object.keys(beforeScope);
        \\  const afterKeys = Object.keys(afterScope);
        \\  if (beforeKeys.length !== afterKeys.length) {
        \\    return true;
        \\  }
        \\  for (const key of afterKeys) {
        \\    if (!Object.prototype.hasOwnProperty.call(beforeScope, key)) {
        \\      return true;
        \\    }
        \\    if (!Object.is(beforeScope[key], afterScope[key])) {
        \\      return true;
        \\    }
        \\  }
        \\  return false;
        \\}
        \\
        \\function collectDirtyBindings(beforeScope, afterScope) {
        \\  const dirty = [];
        \\  const seen = new Set();
        \\  for (const key of Object.keys(beforeScope)) {
        \\    seen.add(key);
        \\    if (!Object.prototype.hasOwnProperty.call(afterScope, key) || !Object.is(beforeScope[key], afterScope[key])) {
        \\      dirty.push(key);
        \\    }
        \\  }
        \\  for (const key of Object.keys(afterScope)) {
        \\    if (seen.has(key)) {
        \\      continue;
        \\    }
        \\    if (!Object.prototype.hasOwnProperty.call(beforeScope, key)) {
        \\      dirty.push(key);
        \\    }
        \\  }
        \\  return dirty;
        \\}
        \\
        \\function normalizeDirtyState(dirtyState) {
        \\  if (Array.isArray(dirtyState)) {
        \\    return { bindings: dirtyState, paths: [], preciseBindings: [] };
        \\  }
        \\  if (!dirtyState || typeof dirtyState !== "object") {
        \\    return { bindings: [], paths: [], preciseBindings: [] };
        \\  }
        \\  return {
        \\    bindings: Array.isArray(dirtyState.bindings) ? dirtyState.bindings : [],
        \\    paths: Array.isArray(dirtyState.paths) ? dirtyState.paths : [],
        \\    preciseBindings: Array.isArray(dirtyState.preciseBindings) ? dirtyState.preciseBindings : [],
        \\  };
        \\}
        \\
        \\const __weiv_observableBrand = Symbol.for("weiv.observable");
        \\
        \\function __weiv_getObservableNode(value) {
        \\  if (!value || (typeof value !== "object" && typeof value !== "function")) {
        \\    return null;
        \\  }
        \\  const node = Reflect.get(value, __weiv_observableBrand);
        \\  if (!node || typeof node !== "object") {
        \\    return null;
        \\  }
        \\  return node;
        \\}
        \\
        \\function __weiv_isObservable(value) {
        \\  return __weiv_getObservableNode(value) !== null;
        \\}
        \\
        \\const __weiv_trackedRootCache = new Map();
        \\const __weiv_trackedSubscribers = new Set();
        \\const __weiv_pendingTrackedPathIds = new Set();
        \\let __weiv_trackedFlushScheduled = false;
        \\
        \\function __weiv_findTrackedRootPlan(bindingName) {
        \\  if (!trackedStateGraph || !Array.isArray(trackedStateGraph.roots)) {
        \\    return null;
        \\  }
        \\  for (const root of trackedStateGraph.roots) {
        \\    if (root && root.bindingName === bindingName) {
        \\      return root;
        \\    }
        \\  }
        \\  return null;
        \\}
        \\
        \\function __weiv_markTrackedPathsForWrite(rootId, fullPath) {
        \\  if (!trackedStateGraph || !Array.isArray(trackedStateGraph.paths)) {
        \\    return;
        \\  }
        \\  for (const pathRecord of trackedStateGraph.paths) {
        \\    if (!pathRecord || pathRecord.rootId !== rootId || typeof pathRecord.path !== "string") continue;
        \\    if (pathRecord.path === fullPath || pathRecord.path.startsWith(`${fullPath}.`)) {
        \\      __weiv_pendingTrackedPathIds.add(pathRecord.pathId);
        \\    }
        \\  }
        \\}
        \\
        \\function __weiv_scheduleTrackedFlush() {
        \\  if (__weiv_trackedFlushScheduled) {
        \\    return;
        \\  }
        \\  __weiv_trackedFlushScheduled = true;
        \\  globalThis.queueMicrotask(() => {
        \\    __weiv_trackedFlushScheduled = false;
        \\    const dirtyPaths = Array.from(__weiv_pendingTrackedPathIds);
        \\    __weiv_pendingTrackedPathIds.clear();
        \\    if (dirtyPaths.length === 0) {
        \\      return;
        \\    }
        \\    for (const instance of Array.from(__weiv_trackedSubscribers)) {
        \\      if (!instance || instance.destroyed) {
        \\        __weiv_trackedSubscribers.delete(instance);
        \\        continue;
        \\      }
        \\      if (typeof instance.updateDirty === "function") {
        \\        const scope = instance.refresh();
        \\        instance.updateDirty({ bindings: [], paths: dirtyPaths }, scope);
        \\      } else if (typeof instance.update === "function") {
        \\        instance.update();
        \\      }
        \\    }
        \\  });
        \\}
        \\
        \\function __weiv_wrapTrackedValue(rootId, currentPath, value) {
        \\  if (!value || typeof value !== "object") {
        \\    return value;
        \\  }
        \\  const proxy = new Proxy(value, {
        \\    get(target, prop, receiver) {
        \\      const result = Reflect.get(target, prop, receiver);
        \\      if (typeof prop !== "string") {
        \\        return result;
        \\      }
        \\      const nextPath = currentPath ? `${currentPath}.${prop}` : prop;
        \\      return __weiv_wrapTrackedValue(rootId, nextPath, result);
        \\    },
        \\    set(target, prop, nextValue, receiver) {
        \\      const updated = Reflect.set(target, prop, nextValue, receiver);
        \\      if (updated && typeof prop === "string") {
        \\        const nextPath = currentPath ? `${currentPath}.${prop}` : prop;
        \\        __weiv_markTrackedPathsForWrite(rootId, nextPath);
        \\        __weiv_scheduleTrackedFlush();
        \\      }
        \\      return updated;
        \\    },
        \\    deleteProperty(target, prop) {
        \\      const updated = Reflect.deleteProperty(target, prop);
        \\      if (updated && typeof prop === "string") {
        \\        const nextPath = currentPath ? `${currentPath}.${prop}` : prop;
        \\        __weiv_markTrackedPathsForWrite(rootId, nextPath);
        \\        __weiv_scheduleTrackedFlush();
        \\      }
        \\      return updated;
        \\    },
        \\  });
        \\  return proxy;
        \\}
        \\
        \\function __weiv_getTrackedRoot(bindingName, value) {
        \\  if (__weiv_isObservable(value)) {
        \\    return value;
        \\  }
        \\  const rootPlan = __weiv_findTrackedRootPlan(bindingName);
        \\  if (!rootPlan) {
        \\    return value;
        \\  }
        \\  const cachedEntry = __weiv_trackedRootCache.get(rootPlan.rootId);
        \\  if (cachedEntry && Object.is(cachedEntry.value, value)) {
        \\    return cachedEntry.proxy;
        \\  }
        \\  const trackedValue = __weiv_wrapTrackedValue(rootPlan.rootId, bindingName, value);
        \\  __weiv_trackedRootCache.set(rootPlan.rootId, { value, proxy: trackedValue });
        \\  return trackedValue;
        \\}
        \\
        \\function collectTrackedDirtyPaths() {
        \\  if (__weiv_pendingTrackedPathIds.size === 0) {
        \\    return [];
        \\  }
        \\  const dirtyPaths = Array.from(__weiv_pendingTrackedPathIds);
        \\  __weiv_pendingTrackedPathIds.clear();
        \\  return dirtyPaths;
        \\}
        \\
        \\function __weiv_hasTrackedRoots() {
        \\  return trackedStateGraph && Array.isArray(trackedStateGraph.roots) && trackedStateGraph.roots.length > 0;
        \\}
        \\
        \\function __weiv_registerTrackedSubscriber(instance) {
        \\  if (__weiv_hasTrackedRoots()) {
        \\    __weiv_trackedSubscribers.add(instance);
        \\  }
        \\}
        \\
        \\function __weiv_unregisterTrackedSubscriber(instance) {
        \\  __weiv_trackedSubscribers.delete(instance);
        \\}
        \\
        \\function flushOwnedBoundary(instance, beforeScope) {
        \\  if (instance.destroyed) {
        \\    return beforeScope;
        \\  }
        \\  const afterScope = instance.refresh();
        \\  const dirtyBindings = collectDirtyBindings(beforeScope, afterScope);
        \\  const dirtyPaths = collectTrackedDirtyPaths();
        \\  if (dirtyBindings.length > 0 || dirtyPaths.length > 0) {
        \\    if (typeof instance.updateDirty === "function") {
        \\      instance.updateDirty({ bindings: dirtyBindings, paths: dirtyPaths }, afterScope);
        \\    } else {
        \\      instance.update();
        \\    }
        \\    return cloneScope(instance.refresh());
        \\  }
        \\  return cloneScope(afterScope);
        \\}
        \\
        \\function runOwnedBoundary(instance, callback) {
        \\  if (instance.cellManaged) return callback();
        \\  let beforeScope = cloneScope(instance.refresh());
        \\  let result;
        \\  try {
        \\    result = callback();
        \\  } catch (error) {
        \\    flushOwnedBoundary(instance, beforeScope);
        \\    throw error;
        \\  }
        \\  beforeScope = flushOwnedBoundary(instance, beforeScope);
        \\  if (result && typeof result.then === "function") {
        \\    return result.finally(() => {
        \\      flushOwnedBoundary(instance, beforeScope);
        \\    });
        \\  }
        \\  return result;
        \\}
        \\
    );
}
