// Internal runtime API. Component integration uses this queue rather than
// introducing an independent scheduler for each kind of state.
type Task = () => void;
type PrepareNotification = () => Task;

function reportErrors(errors: unknown[]) {
  const error = new AggregateError(errors, "Weiv reactive update failed");
  const report = (globalThis as typeof globalThis & { reportError?: (error: unknown) => void }).reportError;
  if (report) report.call(globalThis, error);
  else
    queueMicrotask(() => {
      throw error;
    });
}

export function createReactiveScheduler(
  options: {
    enqueue?: (task: Task) => void;
    reportErrors?: (errors: unknown[]) => void;
    maxWaves?: number;
  } = {},
) {
  const enqueue = options.enqueue ?? ((task: Task) => queueMicrotask(task));
  const report = options.reportErrors ?? reportErrors;
  const maxWaves = options.maxWaves ?? 100;
  if (!Number.isInteger(maxWaves) || maxWaves < 1)
    throw new RangeError("maxWaves must be a positive integer");
  const notifications = new Map<object, PrepareNotification>();
  const jobs = new Map<object, { run: Task }>();
  let scheduled = false;
  let waves = 0;

  function schedule() {
    if (scheduled) return;
    scheduled = true;
    enqueue(flush);
  }

  function flush() {
    const errors: unknown[] = [];
    if (++waves > maxWaves) {
      notifications.clear();
      jobs.clear();
      scheduled = false;
      waves = 0;
      report([new Error(`Weiv reactive updates exceeded ${maxWaves} consecutive waves`)]);
      return;
    }
    // Capture and clear every root before invoking any user listener. Writes
    // during delivery therefore belong to a subsequent wave, even across roots.
    const preparing = Array.from(notifications.values());
    notifications.clear();
    const deliveries: Task[] = [];
    for (const prepare of preparing) {
      try {
        deliveries.push(prepare());
      } catch (error) {
        errors.push(error);
      }
    }
    for (const deliver of deliveries) {
      try {
        deliver();
      } catch (error) {
        errors.push(error);
      }
    }
    // Notifications from multiple roots merge into one component job.
    const running = Array.from(jobs);
    for (const [owner, job] of running) {
      if (jobs.get(owner) !== job) continue;
      jobs.delete(owner);
      try {
        job.run();
      } catch (error) {
        errors.push(error);
      }
    }
    scheduled = false;
    if (notifications.size || jobs.size) schedule();
    else waves = 0;
    if (errors.length) report(errors);
  }

  return {
    notify(owner: object, prepare: PrepareNotification) {
      notifications.set(owner, prepare);
      schedule();
    },
    queueJob(owner: object, job: Task) {
      jobs.set(owner, { run: job });
      schedule();
    },
    cancelJob(owner: object) {
      jobs.delete(owner);
    },
  };
}

// The versioned keys are an internal wire contract. Independently bundled
// compatible copies in one realm must share graph identity and one queue.
export function sharedRuntime<T>(name: string, create: () => T): T {
  const key = Symbol.for(name);
  const existing = Reflect.getOwnPropertyDescriptor(globalThis, key);
  if (existing) return existing.value as T;
  const value = create();
  Object.defineProperty(globalThis, key, { value, enumerable: false, configurable: false, writable: false });
  return value;
}

export const reactiveScheduler = sharedRuntime("weiv.reactivity.scheduler.v1", () =>
  createReactiveScheduler(),
);
