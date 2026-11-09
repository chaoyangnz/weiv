# Simple Component

This is the smallest useful `.weiv` component shape:

```html
<template>
  <section class="card">
    <h1>{{ title }}</h1>
    <p>Count: {{ count }}</p>
    <button @click="increment">Increment</button>
  </section>
</template>

<script lang="ts">
  let title = "Hello Weiv";
  let count = 0;

  function increment() {
    count += 1;
  }
</script>

<style>
  .card {
    display: grid;
    gap: 12px;
    padding: 16px;
  }
</style>
```

## What This Shows

- a `.weiv` single-file component
- plain local state with normal variables
- event binding with `@click`
- template interpolation with `&#123;&#123; ... &#125;&#125;`
- colocated component styles

## Run It

```bash
npx weiv dev src/App.weiv
```

If you want to emit a static browser bundle:

```bash
npx weiv compile src/App.weiv
```
