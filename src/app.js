import { Component, Weiv, observable, action } from '.';

@Component({
  template: `
  <div>
    <span>TODO: {{a}}</span>
    <button onclick="changeProp" style="height: 30px">Try to change props?</button>
    <p>
      <input type="text" />
      <button onclick="onSave" style="height: 30px">Save</button>
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
    this.$emit('save', 1, 2)
  }
}

Weiv.component('todo', Todo)

@Component({
  template: `
  <div>
    <h1 @bind:title="counter">{{firstName}} {{lastName}}</h1><p>{{blogURL}}</p>
    <div @if="counter < 5">Location: {{location.city}} - {{location.country}}</div>
    <p>Countdown: {{counter}}</p>
    <button onclick="minus" style="width: 80px">➖</button>
    <button @on:click="plus" style="width: 80px">➕</button>
    <p>Tip: When counter is less than 5, location will be shown.</p>
    <todo @bind:a="counter" @on:save="onSave"></todo>
  </span>
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

  onSave(a, b) {
    alert(a + ' ' + b)
  }
}

new App().$mount('#app')
