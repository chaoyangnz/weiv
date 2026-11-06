# Weiv Examples

These examples are the current authoring and verification fixtures for `weiv`.

They are not all equal:

- some are human-facing reference examples
- some are focused compiler/runtime fixtures
- some are negative fixtures used to prove diagnostics or unsupported cases

## Reactivity mode

CLI app builds and Vite/Bun plugins use managed reactivity by default. Supported
local and project shared state notify automatically; later DOM patches are batched
into microtasks. Some characterization tests explicitly select the deprecated
legacy emitter to preserve migration coverage. A fixture containing `weivUpdate`
is not a requirement to wrap supported writes in new applications.

See the [current state contract](../../packages/weiv/README.md#state-contract-managed-reactivity-by-default)
and [migration options](../../packages/weiv/README.md#migrating-from-legacy-reactivity).

## Reference Examples

Good small examples to read first:

- [Basic Counter](./basic/basic-counter.weiv)
- [Todo List](./basic/todo-list.weiv)
- [Dashboard Card](./basic/dashboard-card.weiv)
- [Metric Badge](./basic/MetricBadge.weiv)
- [Conditional Toggle](./basic/conditional-toggle.weiv)

## App-Scale Verification

Multi-component verification examples:

- [Kanib](./kanib/README.md)
- [Classic Todo App](./classic-todo/README.md)
- [TodoMVC Verification App](./todomvc/README.md)

Current role:

- `test/examples/kanib` is the larger flagship verification app,
  structured as a routed Kaneo-inspired workspace/issues app
- `test/examples/todomvc` is the main smaller app-scale verification example
- `test/examples/classic-todo` is still useful as a simpler multi-component app

## Focused Runtime / Compiler Fixtures

These exist mainly to pressure-test specific behaviors:

- [Timer Callback](./basic/timer-callback.weiv): callback-driven state updates
- [Imported Helper](./imported-helper/App.weiv): runtime JS import copying
- [Imported TS Helper](./imported-ts-helper/App.weiv): TS helper transpile +
  import rewriting

## Slot / Projection Fixtures

The `slots/` directory is a focused fixture set for:

- default slots
- named slots
- fallback content
- grouped slot templates
- projected updates
- nested slot trees

Useful entry points:

- [Panel](./slots/Panel.weiv)
- [Panel Usage](./slots/PanelUsage.weiv)
- [Card](./slots/Card.weiv)
- [Slot Showcase](./slots/SlotShowcase.weiv)

## Import Fixture

- [Bare Import](./bare-import/App.weiv)

This fixture verifies that bare package imports are preserved through app
bundling and emitted into the browser import map.
