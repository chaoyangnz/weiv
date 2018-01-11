## What is `weiv`

<img src='./weiv.svg' width="80" /> weiv.js - A home-brew UI view library for modern component-based web development.
`Weiv` is the reverse of the word `View`.

## Why `weiv`?

This is an era of evolution with tons of front-end frameworks: React, Angular, Vue, Preact, Ractive, Svelte. Probably like me, you also feel tired to follow this one or another one. So I choose to reinvent the wheel and eat my own dog food.

## How it's like

<img src="https://i.imgur.com/mpTwvNR.gif" width="500">

```javascript
import { Component } from './component';
import Weiv from './weiv';
import { observable, action } from 'mobx';

@Component({
  target: '#app',
  template: `
  <div>
    <h1 @bind:title="counter">{{firstName}} {{lastName}}</h1><p>{{blogURL}}</p>
    <div @if="counter < 5">Location: {{location.city}} - {{location.country}}</div>
    <p>Countdown: {{counter}}</p>
    <button onclick="minus" style="width: 80px">➖</button>
    <button @on:click="plus" style="width: 80px">➕</button>
    <p>Tip: When counter is less than 5, location will be shown.</p>
  </div>
  `
})
export class App {
  firstName = 'Chao'
  lastName = 'Yang'
  blogURL = 'http://yangchao.me'
  location = {
    city: 'Auckland',
    country: 'New Zealand'
  }

  @observable counter = 10
  @action plus() {
    if (this.counter === 10) return
    this.counter += 1
  }
  @action minus() {
    if (this.counter === 0) return
    this.counter -= 1
  }
}

const app = new App()
Weiv.mount(app)
```

## Building blocks & Credits

- [virtual dom](https://github.com/Matt-Esch/virtual-dom)
- [mobx](https://github.com/mobxjs/mobx)
- [jexl-sync](https://github.com/richdyang/jexl-sync)
