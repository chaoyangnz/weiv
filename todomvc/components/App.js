import {Component} from 'weivjs'
import Header from './Header'
import MainSection from './MainSection'

@Component({
  template: `
  <section class="todoapp">
    <todo-header @bind:store="store"></todo-header>
    <todo-main-section @bind:store="store"></todo-main-section>
  </section>
  `,
  props: {
    store: { type: 'any', required: true }
  },
  components: {
    'todo-header': Header,
    'todo-main-section': MainSection
  }
})
class App {}

export default App
