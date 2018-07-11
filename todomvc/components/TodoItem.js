import { Component, action } from 'weivjs'
import TodoTextInput from './TodoTextInput'
import { observable } from 'mobx'

@Component({
  template: `
  <li @bind:class="{completed: todo.completed, editing: editing}">
    <span>
      <todo-text-input @if="editing"
                      @bind:text="todo.text"
                      @bind:editing="editing"
                      @on:save="handleSave"></todo-text-input>
      <span class="view" @else>
        <input class="toggle"
              type="checkbox"
              @bind:checked="todo.completed"
              onchange="handleToggle" autofocus />
        <label ondblclick="handleDoubleClick">
          {{todo.text}} {{completed}}
        </label>
        <button class="destroy"
                onclick="handleDelete"></button>
      </span>
    </span>
  </li>
  `,
  props: {
    store: { type: 'object', required: true },
    todo: { type: 'object', required: true }
  },
  components: {
    'todo-text-input': TodoTextInput
  }
})
class TodoItem {
  @observable editing = false

  get completed() {
    return this.todo.other && this.todo.other.completed ? 'Yes!' : ' . '
  }

  @action handleDoubleClick() {
    this['editing'] = true
    // console.error(this)
  }

  handleSave(text) {
    if (text.length === 0) {
      this.store.deleteTodo(this.todo.id)
    } else {
      this.store.editTodo(this.todo.id, text)
    }
    this.editing = false
  }

  handleToggle() {
    this.store.completeTodo(this.todo.id)
  }

  handleDelete() {
    this.store.deleteTodo(this.todo.id)
  }
}

export default TodoItem
