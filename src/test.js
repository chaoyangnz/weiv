import { Component, Weiv } from './component';

@Component({
  target: '#app',
  template: ''
})
export class App {
  a = 2
}

new App().$mount()

Weiv.startup()
