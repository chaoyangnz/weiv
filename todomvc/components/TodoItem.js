import { Component, observable } from 'weivjs'
import TodoTextInput from './TodoTextInput'

@Component({
  template: `
  <li @bind:class="{completed: todo.completed, editing: todo.id == store.editing}">
    <span>
      <todo-text-input @if="todo.id == store.editing"
                      @bind:text="todo.text"
                      @bind:editing="todo.id == store.editing"
                      @on:save="handleSave"></todo-text-input>
      <span class="view" @if="todo.id != store.editing">
        <input class="toggle"
              type="checkbox"
              @bind:checked="todo.completed"
              onchange="handleToggle" />
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
  // @observable editing = false;

  get completed() {
    return this.todo.other && this.todo.other.completed ? 'Yes!' : ' . '
  }

  handleDoubleClick() {
    this.store.setEditingTodo(this.todo.id)
    // this.editing = true
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
