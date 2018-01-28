import { Component } from 'weivjs'
import _ from 'lodash'
// import classnames from 'classnames'
import { SHOW_ALL, SHOW_COMPLETED, SHOW_ACTIVE } from '../stores/appstate'

@Component({
  template: `
  <footer class="footer">
    <span class="todo-count">
      <strong>{{activeCount}}</strong> {{plural}} left
    </span>
    <ul class="filters">
        <li @for:filter="filters">
          <a @bind:class="{selected: filter == store.filter}"
            style="cursor: 'pointer'"
            @bind:name="filter"
            onclick="handleSetFilter">
            {{titles[filter]}}
          </a>
        </li>
    </ul>
    <button @if="store.completedCount > 0"
            class="clear-completed"
            onclick="handleClearCompleted" >
      Clear completed
    </button>
  </footer>
  `,
  props: {
    store: { type: 'any', required: true }
  }
})
class Footer {

  filters = [SHOW_ALL, SHOW_ACTIVE, SHOW_COMPLETED]
  titles = _.zipObject(this.filters, ['All', 'Active', 'Completed'])

  get activeCount() {
    return this.store.activeCount || 'No'
  }

  get plural() {
    return this.store.activeCount === 1 ? ' item' : ' items'
  }

  handleSetFilter(e) { // TODO how to pass params to event handler??
    this.store.setFilter(e.target.name)
  }

  handleClearCompleted() {
    this.store.clearCompleted()
  }
}

export default Footer
