import { Component } from './component';
import Weiv from './weiv';
import { observable, action } from 'mobx';

@Component({
  template: `
  <span>sss {{a}}</span>
  `,
  props: {
    a: {type: 'number', required: true}
  }
})
export class Todo {

}

Weiv.component('todo', Todo)

@Component({
  target: '#app',
  template: `
  <div>
    <h1 @bind:title="counter">{{firstName}} {{lastName}}</h1><p>{{blogURL}}</p>
    <div @if="counter < 5">Location: {{location.city}} - {{location.country}}</div>
    <p>Countdown: {{counter}}</p>
    <button onclick="minus" style="width: 80px">➖</button>
    <button @on:click.native="plus" style="width: 80px">➕</button>
    <p>Tip: When counter is less than 5, location will be shown.</p>
    <todo @bind:a="counter"></todo>
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

// change data
// setInterval(() => app.countdown(), 1000)

Weiv.startup()
