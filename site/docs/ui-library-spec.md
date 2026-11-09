# UI Library Specification (`@weivjs/ui-*`)

This document defines the implementation contract for Weiv UI packages:

- `@weivjs/ui-core` (headless behavior + accessibility contracts)
- `@weivjs/ui-theme-default` (tokens + default visual styles)

It extends and operationalizes [UI Library Direction](./ui-library-direction.md).

## 1. Goals

- Provide reliable, accessible primitives with predictable behavior.
- Keep behavior and visuals split so themes can evolve independently.
- Borrow proven interaction semantics from Radix-style headless systems.
- Keep API surfaces simple and compiler-friendly for Weiv component authoring.

## 2. Non-Goals

- No monolithic all-in-one component package in v1.
- No CSS-in-JS runtime or style injection system.
- No framework-level animation engine in ui-core.
- No requirement for wrapper/reactive container APIs to use primitives.

## 3. Package Boundaries

## 3.1 `@weivjs/ui-core`

Contains:

- state/controller primitives
- DOM/event semantics
- keyboard interaction contracts
- ARIA wiring helpers
- ID/reference helpers

Must not contain:

- color/spacing/typography/shadow opinions
- CSS class definitions
- assumptions about a specific render layer

## 3.2 `@weivjs/ui-theme-default`

Contains:

- design tokens (`tokens.css`)
- starter class styles (`components.css`)
- theme root helpers (`data-theme`, variants, density)

Must not contain:

- ownership of keyboard/focus behavior
- stateful behavior logic already defined in `ui-core`

## 3.3 Public Surface Naming

Public UI components use the `Wui` prefix.

Examples:

- `WuiDialog`
- `WuiTabs`
- `WuiField`
- `WuiSelect`

`createXController` APIs are internal implementation details and are not the
primary public authoring surface.

## 4. Reference Borrowing Model

## 4.1 We Borrow from Radix-Style Systems

- strict accessibility and keyboard contracts
- deterministic open/close semantics
- composable primitive layering
- controlled/uncontrolled state patterns
- explicit trigger/content role relationships

## 4.2 We Borrow from shadcn-Style Systems

- practical starter styling conventions
- tokenized design surface
- copy-and-adapt friendly default UI theme
- utility-friendly class naming patterns for app teams

## 4.3 We Do Not Copy Directly

- Weiv APIs should remain framework-neutral JS-first controllers in `ui-core`.
- Theme output remains plain CSS and data attributes, not runtime style objects.
- Weiv naming and contracts should be stable across theme packages.

## 5. Rejected Patterns (Intentional)

These are explicit rejections for v1 and should not be introduced accidentally.

1. Render-prop-only composition contracts.
Reason: adds ceremony and harms template readability for Weiv users.

2. Runtime CSS-in-JS dependency for base components.
Reason: conflicts with Weiv preference for static, inspectable CSS output.

3. Large prop-heavy “god components” that hide behavior branches.
Reason: difficult to reason about, test, and document; prefer small primitives.

4. Implicit global singleton UI state managers.
Reason: breaks locality and makes ownership/debugging harder.

5. Requiring framework-specific reactive wrappers to use primitives.
Reason: violates “ordinary state first” framework direction.

6. Animation-required semantics in core behavior APIs.
Reason: accessibility and correctness should not depend on motion implementation.

7. Weak ARIA defaults that require consumers to opt into accessibility.
Reason: baseline behavior must be accessible by default.

## 6. Primitive Roadmap and Contracts

Priority order aligns with existing direction and TODO.

## Phase 1 (Now): Overlay + Disclosure Core

### 6.1 Dialog (core)

Status: in-progress target.

`ui-core` contract:

- open/close/toggle state
- escape key closes when enabled
- outside interaction close semantics (configurable)
- focus restore to trigger/previous active element
- optional modal mode flags (`aria-modal`, focus trap hooks)
- subscribe/unsubscribe notifications

Accessibility baseline:

- `role="dialog"` (or `alertdialog` when declared)
- `aria-labelledby` and `aria-describedby` wiring helpers
- close on `Escape` unless explicitly disabled

`ui-theme-default` support:

- backdrop class
- surface class
- title/description slots
- motion-safe open/close transitions

### 6.2 Disclosure / Accordion primitive base

`ui-core` contract:

- expanded/collapsed state
- toggle/expand/collapse methods
- `aria-expanded` and `aria-controls` link helpers
- keyboard affordance helpers for trigger

Out of initial scope:

- full multi-item accordion roving focus (phase 2+)

### 6.3 Tabs

`ui-core` contract:

- selected tab value/index state
- activation mode: `automatic` or `manual`
- roving focus across tab triggers
- arrow/home/end key support
- orientation support (`horizontal`, `vertical`)
- `aria-selected`, `aria-controls`, `role=tablist/tab/tabpanels` helpers

`ui-theme-default` support:

- tab list, trigger, indicator, panel starter classes

## Phase 2: Form Foundation

### 6.4 Field

`ui-core` contract:

- stable field id generation
- label/help/error linkage (`aria-labelledby`, `aria-describedby`)
- required/invalid/disabled state helpers
- message priority rules (`error` over `help` for active description)

### 6.5 Input primitives (text-like)

`ui-core` contract:

- controlled/uncontrolled helper integration
- disabled/readOnly/invalid state attributes
- field linkage compatibility

### 6.6 Checkbox + Radio

`ui-core` contract:

- checked state and change semantics
- indeterminate support (checkbox)
- group semantics and keyboard behavior (radio group)
- proper role/state attribute helpers

## Phase 3: Selection + Popup Controls

### 6.7 Select

`ui-core` contract:

- open/close controller reuse
- highlighted option state
- typeahead support
- keyboard navigation (up/down/home/end/enter/escape)
- controlled/uncontrolled selected value

### 6.8 Combobox

`ui-core` contract:

- input value + highlighted option coordination
- filtering hook points (consumer-provided)
- listbox popup semantics
- active descendant management

## Phase 4: Overlay Expansion

### 6.9 Popover

- anchor positioning hooks
- outside interaction semantics
- focus return behavior

### 6.10 Dropdown Menu

- hierarchical keyboard navigation
- typeahead
- item roles (normal, checkbox, radio)

### 6.11 Tooltip

- delayed open/close semantics
- hover and focus triggers
- escape and pointer leave behavior

## 7. Radix/shadcn Behavior Matrix

Legend:
- Adopt: behavior should match in spirit.
- Adapt: keep behavior, adjust API shape for Weiv.
- Reject: intentional non-adoption.

1. Controlled/uncontrolled pattern
Decision: Adopt
Notes: keep `createControllableState` foundation.

2. Roving focus for composite widgets
Decision: Adopt
Notes: required for tabs/menu/radio-like controls.

3. `asChild` composition escape hatch
Decision: Adapt
Notes: we should provide a minimal element-binding pattern later without forcing runtime polymorphic wrappers.

4. Data-state/data-disabled attribute styling hooks
Decision: Adopt
Notes: useful for theme package and custom themes.

5. Portal-first requirement for overlays
Decision: Adapt
Notes: support optional portal strategy, not mandatory for all uses.

6. Deeply nested compound React component API shape
Decision: Reject
Notes: not aligned with Weiv JS-controller + template composition approach.

7. Copy-paste styled component bundles (shadcn)
Decision: Adapt
Notes: good for theme examples, but keep ui-core independent and canonical.

8. Runtime styling dependencies in component internals
Decision: Reject
Notes: keep CSS static and inspectable.

## 8. API Shape Conventions (`ui-core`, internal)

- Prefer factory naming: `createXController`, `createXState`.
- Return plain objects with:
  - state getters
  - event methods
  - `subscribe(listener)`
  - `getA11yProps(...)` helpers when appropriate
- Keep options object as first/only argument.
- Avoid positional argument overloads.
- Keep method names explicit (`openDialog`, `closeDialog`) over ambiguous abbreviations.

## 9. Accessibility Baseline Checklist (All Primitives)

Each primitive is not complete until it has:

1. Correct ARIA role/state relationships.
2. Keyboard interaction coverage for expected pattern.
3. Focus behavior defined for open/close/selection transitions.
4. Disabled-state semantics that block unintended interaction.
5. Escape/outside semantics where applicable.
6. Unit tests for state transitions and key events.
7. Integration example in `.weiv` templates.

## 10. Testing Strategy for UI Packages

For each primitive:

- unit tests: controller behavior and edge transitions
- keyboard tests: key-by-key expected state/focus changes
- accessibility tests: ARIA attrs and id linkage
- integration smoke: minimal `.weiv` usage sample

Suggested test locations:

- `test/ui-core/*.test.ts` for behavior contracts
- `test/examples/ui/*` for integration demos

## 11. Documentation Deliverables

Per primitive, add:

1. `What it solves`
2. `Behavior contract`
3. `Keyboard interactions`
4. `Accessibility mapping`
5. `Themed class hooks`
6. `Known limitations`

## 12. Immediate Implementation Queue

1. [x] Implement full dialog contract in `@weivjs/ui-core`.
2. [ ] Add dialog classes (backdrop/surface/header/body/footer) in `ui-theme-default`.
3. [x] Add tabs controller in `ui-core` with roving focus.
4. [ ] Add field wiring helpers in `ui-core` and extend starter input/field styles.
5. [x] Add tests for dialog + tabs + field baseline behavior.

## 12.1 Storybook-First Phase Reviews

Storybook is required from the beginning of UI library implementation.

For each completed phase:

1. Add or update stories for all primitives in that phase.
2. Validate keyboard and interaction behavior manually in Storybook.
3. Review visual quality (spacing, states, tokens, contrast) in Storybook.
4. Log phase sign-off only after Storybook review + tests both pass.

## 13. Versioning and Stability

- Before `1.0`, API may evolve but should preserve naming conventions.
- Breaking behavior changes must update this spec and package READMEs together.
- “Experimental” primitives should be marked explicitly in docs until stable.
