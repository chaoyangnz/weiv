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
  @action countdown() {
    if (this.counter === 0) return
    this.counter -= 1
  }
}

const app = new App()
Weiv.mount(app)

// change data
setInterval(() => app.countdown(), 1000)

Weiv.startup()
