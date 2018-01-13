export { Component } from './component'
export { observable, action, computed } from 'mobx'

export const Weiv = {
  $components: new Map(),

  component(tag: string, componentClass: any) {
    this.$components.set(tag, componentClass)
  }
}
