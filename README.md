## What is `weiv`

<img src='./weiv.svg' width="80" /> weiv.js - A home-brew UI view library for modern component-oriented web development.
`Weiv` is the reverse of the word `View` or `微V` in Chinese which means micro-view literally.

## Why `weiv`?

This is an era of front-end evolution with tons of front-end frameworks: React, Angular, Vue, Preact, Ractive, Svelte. Probably like me, you also feel tired to follow this one or another one. So I choose to reinvent the wheel and eat my own dog food.

## How it's like

<img src="https://i.imgur.com/7zDlvn1.gif" width="500">

[![Edit weiv-demo](https://codesandbox.io/static/img/play-codesandbox.svg)](https://codesandbox.io/s/m7k55r39p9?autoresize=1&expanddevtools=1&hidenavigation=1)
```javascript
import { Component, observable, action } from 'weivjs'

@Component({
  template: `
  <div>
    <span>TODO: {{a}}</span>
    <button onclick="changeProp" style="height: 30px">Try to change props?</button>
    <p>
      <slot>
        <p>show when no slot</p>
      </slot>
      <p>
        <input type="text" oninput="onInput"  />
        <button onclick="onSave" style="height: 30px">Save</button>
        <span> {{input}} </span>
      </p>
      <ul>
        <slot name="item">show when no item slot</slot>
      </ul>
    </p>
  </div>
  `,
  props: {
    a: {type: 'number', required: true}
  },
  events: {
    save: {}
  }
})
export class Todo {
  changeProp() {
    try {
      this.a = 0
    } catch (err) {
      alert(err.message)
    }
  }

  onSave() {
    this.$emit('save', this.input, '')
  }

  @observable
  input = ''

  onInput(e) {
    this.input = e.target.value
    console.log('on input %o', e)
  }
}

@Component({
  template: `
  <div>
    <h1 @bind:title="counter">{{firstName}} {{lastName}}</h1><p>{{blogURL}}</p>
    <div @if="counter < 5">Location: {{location.city}} - {{location.country}}</div>
    <p>Countdown: {{counter}}</p>
    <button onclick="minus" style="width: 80px">➖</button>
    <button @on:click="plus" style="width: 80px">➕</button>
    <p>Tip: When counter is less than 5, location will be shown.</p>
    <todo @bind:a="counter" @on:save="onSave">
      <div>this is a default slot</div>
      <li slot="item">item1</li>
      <li slot="item">item2</li>
      <span>another default slot</span>
    </todo>
  </span>
  `,
  components: {'todo': Todo}
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

  onSave(a, b) {
    alert(`Are you sure to save: ${a} ${b}?`)
  }
}

new App().$mount('#app')
```

## Building blocks & Credits

- [virtual dom](https://github.com/Matt-Esch/virtual-dom)
- [mobx](https://github.com/mobxjs/mobx)
- [jexl-sync](https://github.com/richdyang/jexl-sync)

## TODOs

- [x] Add slots support
- [x] Refine directive structure
- [ ] Add scope to support `for ... in`
- [x] Enhance events support
- [ ] Add lifecycle hooks
- [ ] Optimise: cache subtree via vdom-trunk
- [ ] Optimise: batch update via main-loop
- [ ] Optimise: try to use zone.js intead of mobx `autorun`
- [ ] Write a UI component library like ElementUI
