import { observable, subscribe } from "./observable.ts";
import { reactiveScheduler } from "./reactive-core.ts";
export { isObservable } from "./observable.ts";
export { bindingObject, bindingIterator } from "./binding.ts";

// Internal storage for compiler-managed bindings. A box reuses the observable
// graph for both root replacement and nested writes; there is no cell scheduler.
export type Cell<T> = { value: T };

const classNameDescriptor = Object.getOwnPropertyDescriptor;
const defineClassName = Object.defineProperty;

// Cell calls and assignment adapters remove native binding-name inference.
// Run before user static initialization; never replace a user name method/getter.
export function initializeClassName(value: Function, name: string): void {
  const descriptor = classNameDescriptor(value, "name");
  if (descriptor?.value === "" && descriptor.configurable === true &&
      descriptor.enumerable === false && descriptor.writable === false) {
    defineClassName(value, "name", { value: name });
  }
}

// Keep native assignment/destructuring in control of GetValue/PutValue timing.
// Creating a target must not read a binding that may still be uninitialized.
export function assignmentTarget<T>(read: () => T, write: (value: T) => unknown): Cell<T> {
  return { get value() { return read(); }, set value(value: T) { write(value); } };
}

export function cellAssignmentTarget<T>(cell: () => Cell<T>): Cell<T> {
  return assignmentTarget(() => cell().value, value => { cell().value = value; });
}

// Keep an identifier call's undefined receiver after lowering it to cell.value.
// Do not check callability here: arguments must still evaluate before a call to
// a non-callable value throws. Nullish values retain optional-call short circuiting.
export function unbindCellValue<T>(value: T): T {
  if (value == null) return value;
  return ((...args: unknown[]) => Reflect.apply(value as unknown as (...args: unknown[]) => unknown, undefined, args)) as unknown as T;
}

export function createCell<T>(value: T): Cell<T> {
  const cell = observable({ value });
  // Establish the root edge before subscriptions: shared values can change
  // before any template has read this cell.
  void cell.value;
  return cell;
}

// Normalize before a root assignment, so its expression result and subsequent
// reads of the binding refer to the same tracked object. Frozen values go through
// the box's snapshot validation; mutable objects use the graph directly.
export function normalizeCellValue<T>(value: T): T {
  if (value === null || typeof value !== "object") return value;
  if (Object.isFrozen(value)) return createCell(value).value;
  return observable(value) as T;
}

// One instance lives in each build-generated companion module. Public ESM
// bindings remain in their source module; these slots only publish changes.
// A placeholder cell allows cyclic consumers to subscribe before initialization.
export function createModuleState() {
  const cells = new Map<string, Cell<unknown>>();
  return {
    getCell(name: string): Cell<unknown> {
      let cell = cells.get(name);
      if (!cell) {
        cell = createCell<unknown>(undefined);
        cells.set(name, cell);
      }
      return cell;
    },
    publish(name: string, value: unknown) {
      const existing = cells.get(name);
      if (existing) {
        existing.value = value;
        void existing.value;
      } else cells.set(name, createCell(value));
    },
  };
}

export function afterModuleWrite<T>(
  module: () => ReturnType<typeof createModuleState>, name: string,
  result: T, read: () => unknown,
): T {
  // Both lookups occur after the original write expression succeeds. In
  // particular, a throwing RHS must not read a binding or publish a change.
  module().publish(name, read());
  return result;
}

export function initialModuleValue<T>(module: ReturnType<typeof createModuleState>, name: string, value: T): T {
  module.publish(name, value);
  return value;
}

// The scope owns subscriptions and a component job, never shared values.
export function createCellScope<Key>(update: (dirty: ReadonlySet<Key>) => void) {
  const owner = {};
  const registrations = new Set<() => void>();
  const dirty = new Set<Key>();
  let disposed = false;
  const run = () => {
    if (disposed) return;
    const changes = new Set(dirty);
    dirty.clear();
    if (changes.size) update(changes);
  };

  return {
    watch<T>(cell: Cell<T>, key: Key) {
      if (disposed) throw new Error("Cannot subscribe through a disposed Weiv cell scope");
      const unsubscribe = subscribe(cell, () => {
        if (disposed) return;
        dirty.add(key);
        reactiveScheduler.queueJob(owner, run);
      });
      const stop = () => {
        unsubscribe();
        registrations.delete(stop);
      };
      registrations.add(stop);
      return stop;
    },
    dispose() {
      if (disposed) return;
      disposed = true;
      reactiveScheduler.cancelJob(owner);
      for (const stop of registrations) stop();
      dirty.clear();
    },
  };
}
