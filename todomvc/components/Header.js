import {Component} from 'weivjs'
import TodoTextInput from './TodoTextInput'

@Component({
  template: `
  <header class="header">
    <h1>todos</h1>
    <todo-text-input newtodo="true"
                   @on:save="handleSave"
                   placeholder="What needs to be done?" />
  </header>
  `,
  props: {
    store: { type: 'any', required: true }
  },
  components: {
    'todo-text-input': TodoTextInput
  }
})
class Header {
  handleSave(text) {
    if (text.length !== 0) {
      this.store.addTodo(text)
    }
  }
}

export default Header
