# Template Syntax

Weiv templates stay close to ordinary HTML, then add a small set of
component-focused directives. Directives always start with a symbol:

- `:` binds an expression to an attribute or component prop
- `@` listens for a DOM or component event
- `#` controls template structure

This keeps ordinary HTML attributes—including `if`, `else`, and `for`—out of
the directive namespace.

## Interpolation

Use <code v-pre>{{ ... }}</code> to render values into the template.

```html
<template>
  <section>
    <h1>{{ title }}</h1>
    <p>Count: {{ count }}</p>
  </section>
</template>

<script lang="ts">
  let title = "Hello Weiv";
  let count = 0;
</script>
```

## Events

Use `@event` for DOM event handlers.

```html
<template>
  <button @click="increment">Increment</button>
</template>

<script lang="ts">
  let count = 0;

  function increment() {
    count += 1;
  }
</script>
```

## Attribute Binding

Use `:` when an attribute should come from an expression.

```html
<template>
  <button :disabled="count >= limit" :aria-label="buttonLabel()">
    Add
  </button>
</template>

<script lang="ts">
  let count = 0;
  let limit = 5;

  function buttonLabel() {
    return count >= limit ? "Limit reached" : "Add one";
  }
</script>
```

`:` works for ordinary DOM attributes and component props.

```html
<template>
  <MetricCard :label="'Open issues'" :value="issueCount" />
</template>
```

## Conditionals

Use `#if="..."` to render a branch only when the expression is truthy. Put
`#else` on the immediately following sibling for its fallback branch.

```html
<template>
  <p #if="count === 0">Nothing yet.</p>
  <p #else>Current count: {{ count }}</p>
</template>
```

## Lists

Use `#for="item in items"` to repeat an element or component.

```html
<template>
  <ul>
    <li #for="item in visibleItems()">{{ item.label }}</li>
  </ul>
</template>

<script lang="ts">
  let items = [
    { label: "Ship docs", done: false },
    { label: "Polish examples", done: true }
  ];

  function visibleItems() {
    return items.filter((item) => !item.done);
  }
</script>
```

## Slots

Use `<slot>` inside a component to expose content regions.

```html
<template>
  <article class="card">
    <header>
      <slot name="header">
        <h2>Default header</h2>
      </slot>
    </header>

    <section>
      <slot></slot>
    </section>
  </article>
</template>
```

Then fill those regions from the parent with `slot:name`.

```html
<template>
  <Card>
    <h2 slot:header>{{ title }}</h2>
    <p>{{ body }}</p>
  </Card>
</template>
```

## Component Example

This combines the main template features in one place.

```html
<template>
  <section class="panel">
    <h2>{{ title }}</h2>
    <button @click="toggleDone">
      {{ showDone ? "Hide done" : "Show done" }}
    </button>

    <p #if="visibleItems().length === 0">No items to show.</p>

    <ul #else>
      <li #for="item in visibleItems()">
        <span :class="item.done ? 'done' : ''">{{ item.label }}</span>
      </li>
    </ul>
  </section>
</template>
```

## Legacy Syntax

`bind:name` and `on:event` are accepted temporarily for compatibility, but
Weiv `0.1.1` reports `directive.deprecated_syntax` warnings for them. Prefer
`:name` and `@event` in new code and migrate existing templates when touched.

Bare `if`, `else`, and `for` are ordinary HTML attributes. They no longer
activate structural behavior; use `#if`, `#else`, and `#for` instead.

## Next Step

Use [Simple Component](./simple-component.md), [Shared State](./shared-state.md),
and [Router Example](./router-example.md) for larger end-to-end examples.
