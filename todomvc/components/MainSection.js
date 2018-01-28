import {Component} from 'weivjs'
import TodoItem from './TodoItem'
import Footer from './Footer'

@Component({
  template: `
  <input class="toggle-all"
    type="checkbox"
    @bind:checked="store.completedCount == store.todos.length"
    onchange="onChange" />
  `,
  props: {
    store: { type: 'any', required: true }
  }
})
class ToggleAll {
  onChange() {
    this.store.completeAll()
  }
}

@Component({
  template: `
  <ul class="todo-list">
    <todo-item @for:todo="store.visibleTodos" @bind:todo="todo" @bind:store="store"></todo-item>
  </ul>
  `,
  props: {
    store: { type: 'any', required: true }
  },
  components: {
    'todo-item': TodoItem
  }
})
class TodoList {}

@Component({
  template: `
  <section class="main">
    <todo-toggle-all @bind:store="store" @if="store.todos.length > 0"></todo-toggle-all>
    <todo-list @bind:store="store"></todo-list>
    <todo-footer @bind:store="store" @if="store.todos.length > 0"></todo-footer>
  </section>
  `,
  props: {
    store: { type: 'any', required: true }
  },
  components: {
    'todo-list': TodoList,
    'todo-toggle-all': ToggleAll,
    'todo-footer': Footer
  }
})
class MainSection {}

export default MainSection
