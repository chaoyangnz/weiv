# Framework Vision

The public framework direction now lives in [Architecture](./architecture.md).

Use that page for:

- product direction
- core principles
- component model
- compiler/runtime architecture

## 7.4 Styling Model

Scoped component styles should be supported by default.

The style system should prefer:

- ordinary CSS
- predictable scoping
- low abstraction

The framework should avoid forcing:

- CSS-in-JS
- runtime styling primitives
- nonstandard styling DSLs

## 8. Reactivity Model

This is the most important design constraint in the project.

### 8.1 Desired Outcome

Developers should be able to write ordinary-looking component state without explicitly wrapping each state value in framework-specific reactive containers.

The preferred mental model is:

- component instance holds state
- template depends on state
- framework/compiler tracks enough structure to update efficiently

### 8.2 Non-Goals

The default model should not require:

- explicit per-field wrappers
- explicit computed wrappers for simple derivations
- framework-wide dependence on proxy semantics in application code

### 8.3 Acceptable Hidden Mechanisms

Implementation-wise, `weiv` may use:

- compiler transforms
- property instrumentation
- generated update plans
- runtime subscriptions internal to the framework

The important rule is:

the implementation mechanism is allowed to be sophisticated, but the authoring model should remain simple.

### 8.4 Derived State

Simple derived values should be expressible as:

- local computed constants or functions
- ordinary helper functions
- compile-time analyzable template expressions

If the framework later introduces special primitives for expensive or async derivation, they should remain advanced tools, not the default expectation.

## 9. Compiler Responsibilities

The `weiv` compiler should own:

- parsing `.weiv` single-file components
- validating component sections
- binding template symbols to script scope
- transforming scoped CSS
- compiling templates to optimized runtime instructions
- producing sourcemaps
- emitting TypeScript-friendly artifacts for tooling

The compiler is a core product, not just an implementation detail.

## 10. Runtime Responsibilities

The runtime should be intentionally small.

Expected responsibilities:

- mount component trees
- create/destroy component instances
- connect compiled template instructions to DOM operations
- schedule updates
- coordinate event handlers
- support lifecycle hooks

The runtime should avoid becoming:

- a large general-purpose reactive graph engine
- a kitchen-sink state library
- an unbounded plugin host

## 11. Tooling Integration

The likely initial tooling direction should include:

- a dependency-light `weiv` CLI
- Bun-friendly TypeScript workflow support
- TypeScript language tooling hooks
- source map support
- test runner compatibility

The first-class developer experience should include:

- good diagnostics for template symbol errors
- easy local dev startup
- stable stack traces
- clear compiled output inspection

## 12. Rendering Strategy

The first implementation should prioritize client-side rendering.

Reason:

- it reduces initial complexity
- it lets the component model and compiler stabilize first
- it avoids mixing core framework design with SSR architecture too early

Later possible stages:

- SSR rendering API
- hydration/resume story
- static-site or partial-prerender adapters

These should be future phases, not day-one obligations.

## 13. Routing and Data

Data-fetching should not be required to prove the core framework.

A runtime-level router now exists (`packages/weiv/src/runtime/router.ts`) as a companion
module. It integrates with the existing `mountIntoBoundary`/`destroy` component
lifecycle and uses the observable runtime for reactive route state. It was
implemented as a pure runtime module with no compiler changes required.

The first `weiv` milestone should still succeed without:

- a built-in cache layer
- a framework-owned GraphQL client

These can evolve later as packages or companion projects.

## 14. MVP Scope

The v1 MVP should include only the minimum viable framework foundation:

- `.weiv` single-file component parser
- `<template>`, `<script lang="ts">`, `<style>` sections
- component props
- conditionals
- loops
- event binding
- scoped CSS
- small browser runtime
- Vite integration
- source maps
- one or two realistic example apps

The MVP should not include:

- SSR
- transitions system
- complex forms package
- resource cache system
- custom animation DSL

Note: a runtime-level router now exists as a companion module outside the MVP
core.

## 15. Evolution Path

The intended maturity path should be:

### Phase 1: Spec and Syntax Stability

- lock the conceptual model
- lock SFC shape
- lock the default state philosophy
- lock compiler/runtime responsibilities

### Phase 2: Parser, Compiler, Minimal Runtime

- parse components
- mount simple components
- support props, events, conditional rendering, loops
- prove that the authoring model feels right

### Phase 3: Tooling and Developer Experience

- Vite integration
- diagnostics
- source maps
- editor support
- examples

### Phase 4: Ecosystem Foundations

- ~~router~~ (done — runtime-level, `packages/weiv/src/runtime/router.ts`)
- testing utilities
- async resource primitives if actually needed
- form helpers

### Phase 5: Advanced Delivery Modes

- SSR
- hydration
- static generation
- adapters

## 16. Deliberately Deferred Questions

These questions are important, but should not block the first spec baseline:

- should the default script model be purely module-based or allow an optional object wrapper pattern?
- what exact syntax should templates use for interpolation and control flow?
- how much JavaScript should template expressions allow?
- should styles default to scoped or opt-in scoped?
- what should component-to-component event typing feel like?
- should the compiler target DOM instructions directly or an intermediate representation first?
- what should the package split be across compiler/runtime/tooling?

These are design decisions for the next stage, not reasons to delay the specification.

## 17. Design Constraints

Every design decision in `weiv` should be tested against these questions:

1. Does this make ordinary component code more readable?
2. Does this avoid forcing framework-specific wrappers into everyday state?
3. Does this preserve clear template/script/style separation?
4. Does this keep the runtime smaller when a compiler can do the work?
5. Does this improve TypeScript and tooling quality rather than fight it?
6. Is this something a product team would still enjoy using after six months?

If a proposed feature fails those tests, it should be rejected or deferred.

## 18. Success Criteria

`weiv` succeeds if developers can say:

- “I can write components naturally.”
- “I do not have to adopt a strange state wrapper model just to render UI.”
- “My templates stay readable.”
- “My logic stays in TypeScript instead of leaking into markup.”
- “The framework helps me more than it asks from me.”

That is the real product target.
