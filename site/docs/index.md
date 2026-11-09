---
layout: home
title: Weiv.js

hero:
  name: ""
  text: "Frontend, with room to breathe."
  tagline: "A compiler-first frontend framework for single-file components, direct DOM updates, and a shared reactive runtime."
  image:
    src: /assets/weiv.png
    alt: Weiv
  actions:
    - theme: brand
      text: Get Started
      link: /getting-started
    - theme: alt
      text: Read the Docs
      link: /architecture

features:
  - title: Compiler-First
    details: Author in `.weiv` single-file components and let compile time carry more of the framework’s weight.
  - title: Direct DOM
    details: Emit focused DOM updates instead of hauling a framework-wide virtual DOM through runtime.
  - title: Low-Ceremony Reactivity
    details: Keep local state close to the component with less wiring, and reach for shared state only when it truly helps.
  - title: Shared Reactive Core
    details: Supported local and project shared state use one tracking and scheduling mechanism; external mutable data has explicit boundaries.
---

# Why Weiv

Weiv is building toward a frontend model that stays simple at the authoring
surface while pushing more precision into compile time.

Start with [Getting Started](./getting-started.md) for installation and CLI
usage, then move on to [Simple Component](./simple-component.md),
[Shared State](./shared-state.md), [VS Code Extension](./vscode-extension.md),
[Router Example](./router-example.md), [Architecture](./architecture.md), and
[Runtime API](./runtime-api.md) as you go deeper.
