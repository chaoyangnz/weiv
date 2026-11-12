# Core Architecture

Weiv is a compiler-first frontend framework for `.weiv` single-file components.
The compiler owns component structure, dependency discovery, update regions, and
the shape of generated DOM code. The runtime keeps those generated components
alive, tracks supported shared state, and applies batched updates.

::: info Source and release status
This guide describes the current source checkout. Published versions may lag
behind compiler and runtime features documented here.
:::

## Design constraints

Weiv is built around six constraints:

1. Templates, TypeScript, and CSS stay separate inside one component file.
2. Ordinary local state is the default; explicit observable wrappers remain an
   escape hatch for external mutable data.
3. The compiler emits retained DOM operations without a framework-wide virtual
   DOM.
4. State writes are immediate and DOM delivery is batched into a microtask.
5. Project modules participate in one managed graph with stable module identity.
6. Unsupported state boundaries produce source-located diagnostics.

These are product boundaries, not implementation details. They shape the
component contract, build plugins, runtime API, and testing strategy.

## System map

```text
author source
    |
    +-- .weiv component ----> compiler pipeline ----> generated DOM module
    |                                                    |
    +-- managed JS/TS ------> shared-state transform ----+
                                                         |
build entry ---------------------------------------------+
                                                         v
                                                browser application
                                                         |
                                     observable router and SDK modules
```

The package has four main layers:

| Layer | Responsibility |
| --- | --- |
| Authoring | `.weiv` sections, TypeScript script bindings, CSS, props, events, slots, and template directives |
| Compilation | SFC parsing, script facts, binding analysis, LIR, browser render trees, update-region planning, diagnostics, and code emission |
| Build integration | CLI app builds plus Vite and Bun adapters that compile component graphs and managed project modules together |
| Runtime | Component mounting and destruction, observable state, microtask scheduling, direct DOM patches, and routing |

## Compilation pipeline

Every component moves through explicit representations:

```text
SFC document
  -> template AST
  -> ScriptFacts + TemplateBindings
  -> target-neutral LIR
  -> browser RenderTree
  -> BrowserComponent
  -> JavaScript and scoped CSS
```

The compiler separates parsing, semantic analysis, lowering, browser planning,
and emission so each stage has a narrow contract.

### SFC parsing

The SFC parser finds the template, script, and style sections. The template
parser then builds an AST while preserving source spans. Script and style remain
raw text at this layer because template parsing does not need TypeScript or CSS
semantics.

### Semantic analysis

The Rust script backend extracts TypeScript facts that the compiler needs:
declarations, writes, mutations, imports, and handler shapes. The template
binder connects those facts to interpolation, bindings, events, branches, loops,
child props, and slots.

This produces two complementary views:

- `ScriptFacts` describe what the script owns and may mutate.
- `TemplateBindings` describe what template observation points may read.

The resulting analysis is lexical and bounded. It is intentionally smaller than
a promise to infer arbitrary JavaScript behavior.

### Lowering and browser planning

Lowering converts the bound component into target-neutral LIR. The browser
backend turns LIR into a `RenderTree`, then assigns update regions. A region is
the smallest generated unit that refreshes one part of retained DOM, such as:

- text interpolation
- a bound attribute
- a conditional branch
- a loop
- a child component
- projected slot content

The emitter produces direct DOM operations such as `createDom`, `updateDom`,
`destroyDom`, and focused region updates. CSS is scoped at the same component
boundary.

## Managed state and scheduling

Supported template-dependent local state becomes reactive automatically. The
compiler discovers dependencies from the template and the supported writes in
the script. Template handlers, timers, Promises, and external callbacks all use
the same scheduling path.

The timing contract is:

1. A supported state write updates JavaScript state immediately.
2. The write records dirty dependencies.
3. DOM work is queued in a microtask.
4. Dirty bindings select component update jobs and their regions.
5. Generated patch code updates only the regions that may have changed.

Initial mounting is synchronous. Subsequent DOM changes are batched. Destroying
a component releases its subscriptions and cancels pending work without
destroying shared state.

The compiler can fall back to a broader component update when precise analysis
is not safe. This model prefers a correct coarse update over a silent stale UI.
See [Runtime Scheduling](./runtime-scheduling.md) for the ordering guarantees.

## Project graph and shared modules

A component compiled by itself can manage its local state, but project-wide
shared state needs a managed graph. The CLI app builder and the Vite and Bun
plugins:

- discover static component imports from configured entry points
- compile the component graph together
- transform supported JavaScript and TypeScript modules inside the managed root
- preserve canonical module identity and native live exports
- rebuild the graph when original managed sources change

The managed root is an explicit ownership boundary. Code outside it, including
`node_modules` by default, keeps its normal behavior. External mutable data needs
an observable or subscription adapter.

Standalone `emit js` manages component-local state. `compile` and the bundler
plugins additionally manage project modules. This distinction is central to
correctness and diagnostics.

See [Reactivity](./reactivity.md),
[Shared State](./shared-state.md), and [Bundling](./bundling.md) for the
author-facing contract.

## Runtime modules

The runtime stays small and stays below the component contract:

| Module | Role |
| --- | --- |
| Managed scheduler | Merges supported local/shared writes and queues component patches |
| `weiv:observable` | Explicit proxy, subscription, snapshot, and notification support for external mutable data |
| `weiv:router` | History and hash routing, nested outlets, guards, links, lazy routes, and scroll restoration |

Components and the router share the same observable and scheduling foundation.
The router mounts emitted component modules through the generated component
lifecycle contract without adding a new template syntax.

See [Runtime API](./runtime-api.md) for module-level details.

## Diagnostics and inspection

Diagnostics are part of the framework contract. When a pattern cannot be tracked
correctly, the compiler should explain the unsupported boundary at the source
location instead of producing uncertain output.

The compiler can expose intermediate representations:

```bash
npx weiv analyze component path/to/App.weiv --json
npx weiv emit ast path/to/App.weiv
npx weiv emit sir path/to/App.weiv
npx weiv emit lir path/to/App.weiv
npx weiv emit render-tree path/to/App.weiv
npx weiv emit invalidation-graph path/to/App.weiv
```

`emit invalidation-graph` is the primary tool for answering which bindings drive
which regions and where mutations enter the update graph.

## Source organization

| Area | Location |
| --- | --- |
| Compiler entry and pipeline | `src/` |
| Rust script and cell analysis | `libs/parser-backend/` |
| Runtime and bundler adapters | `packages/weiv/src/` |
| Public CLI launcher | `packages/weiv/bin/` |
| Generated runtime typings | `packages/weiv/types/` |
| Browser and component coverage | `test/` |
| Public guides | `site/docs/` |

For the compiler-stage ownership map, see the
[compiler architecture record](https://github.com/neucine/weiv/blob/main/docs/compiler/ARCHITECTURE.md).
For public command and module signatures, continue to the
[API Guide](./api-guide.md).

## Intended boundaries

Weiv currently targets browser-rendered applications with `.weiv` components and
a small runtime. Server rendering, hydration, portals, scoped slot props, and
full cross-platform native compiler artifacts are outside the current core
contract unless a guide explicitly says otherwise.
