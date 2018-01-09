import { Component } from './component';
import Weiv from './weiv';

@Component({
  target: '#app',
  template: `
  <div>
    <h1>{{firstName}} {{lastName}}</h1><p>{{blogURL}}</p>
    {{#manager}}Manager: {{firstName}} {{lastName}}{{/manager}}
  </div>
  `
})
export class App {
  firstName = 'Christophe'
  lastName = 'Coenraets'
  blogURL = 'http://coenraets.org'
  manager = {
    firstName: 'John',
    lastName: 'Smith'
  }
}

Weiv.mount(new App())

Weiv.startup()
