import debug from 'debug'

export { Component } from './component'
export { observable, action, computed } from 'mobx'

export const Weiv = {
  $components: new Map(),

  component(tag: string, componentClass: any) {
    this.$components.set(tag, componentClass)
  }
}

// set all debug to console.debug
debug.log = console.log.bind(console)
