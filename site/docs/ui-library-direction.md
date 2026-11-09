# UI Library Direction (`@weivjs/ui-*`)

This project now has an initial UI library scaffold split into two layers:

- `@weivjs/ui-core`: headless behavior primitives
- `@weivjs/ui-theme-default`: default token theme + starter component styles

## Why This Split

- keep `weiv` core runtime-light and compiler-first
- enforce behavior/accessibility discipline separately from visual style
- allow multiple theme packages without changing behavioral contracts

## Package Contract

### `@weivjs/ui-core`

- no visual opinion
- no CSS dependency
- exposes behavior/state helpers for component authoring

Current starter exports:

- `createId(prefix?)`
- `createControllableState(initialValue)`
- `createDialogController({ initialOpen? })`
- `createDisclosureController({ initialExpanded? })`

### `@weivjs/ui-theme-default`

- token variables (`tokens.css`)
- starter class styles (`components.css`)
- tiny helper export (`applyThemeAttributes`)

Current token families:

- color
- spacing
- radius
- font
- shadow
- motion

## Immediate Next Build Order

1. Dialog primitive contract in `ui-core` (focus restore + escape semantics)
2. Tabs + disclosure primitives
3. Field primitives (label/help/error wiring)
4. Select/combobox behaviors
5. Theme variants and density modes in `ui-theme-default`

## Usage Baseline

```js
import { createDialogController } from "@weivjs/ui-core";
import "@weivjs/ui-theme-default/tokens.css";
import "@weivjs/ui-theme-default/components.css";
```
