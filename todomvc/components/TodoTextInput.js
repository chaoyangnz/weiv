import { Component, observable } from 'weivjs'

@Component({
  template: `
  <input @bind:class="{edit: editing, newtodo: newtodo}"
         type="text"
         @bind:placeholder="placeholder"
         autofocus="true"
         @bind:value="text || value"
         onblur="handleBlur"
         onchange="handleChange"
         onkeydown="handleSubmit" />
  `,
  props: {
    text: { type: 'string' },
    placeholder: { type: 'string' },
    editing: { type: 'boolean' },
    newtodo: { type: 'boolean' }
  },
  events: {
    save: { type: 'function' }
  }
})
class TodoTextInput {
  @observable value = ''; // this.value = this.props.text || ''

  handleSubmit = (e) => {
    const value = e.target.value.trim()
    if (e.which === 13) {
      this.$emit('save', value)
      if (this.newtodo) {
        this.value = ''
      }
    }
  }

  handleChange = (e) => {
    this.value = e.target.value
  }

  handleBlur = (e) => {
    if (!this.newtodo) {
      this.$emit('save', e.target.value)
    }
  }
}

export default TodoTextInput
