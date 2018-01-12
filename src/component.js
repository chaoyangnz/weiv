// @flow
import { VNode, h } from 'virtual-dom'
import _ from 'lodash'
// import Hogan from 'hogan.js'
// import parser from 'vdom-parser'
import { compile } from './template'
import { EventEmitter } from 'fbemitter'
import Weiv from './weiv'

export type Prop = {
  type: Function,
  default: any,
  required: boolean
}

export type Options = {
  name: string,
  target?: string,
  template?: string,
  props?: {[string]: Prop}
}

export type ComponentMeta = {
  $name: ?string,
  $target: ?string,
  $template: ?any,
  $props: {[string]: Prop},
  $components: {[string]: any},
  $render: () => VNode,
  $isRoot: () => boolean,
}

function createComponentMeta(options: Options) {
  const meta: any = {}
  if (options.target) {
    meta.$target = options.target
  }
  if (options.props) {
    meta.$props = _.cloneDeep(options.props)
  }
  if (options.components) {
    meta.$components = _.cloneDeep(options.components)
  }
  meta.$render = function () {
    if (this.$template) {
      const vdom = this.$template.render(this)
      this.$vdom = vdom
    } else {
      this.$vdom = h('div', {}, [])
    }
  }

  meta.$isRoot = function () {
    return !!this.$target
  }
  meta.$lookupComponent = function (tag) {
    let componentClass = this.$components[tag]
    if (componentClass) return componentClass
    return Weiv.$components[tag]
  }
  if (options.template) {
    meta.$template = compile(options.template.trim(), meta)
  }

  return meta
}

export class ComponentMixin {
  // only mounted component has a root vdom tree
  $vdom: ?VNode = null
  $dom: ?HTMLElement = null
  // parent component
  $parent: ?ComponentMixin = null
  $root: ?ComponentMixin = null
  // event emitter
  $emitter: EventEmitter = new EventEmitter()

  constructor() {
    // init instance from meta
    // trigger $created lifecycle hook
  }

  // create component props properties as per $props declaration
  initProps() {
    // TODO
  }
}

export function Component(options: Options) {
  return function decorator(ComponentClass: any) {
    Object.assign(ComponentClass.prototype, createComponentMeta(options)) // share meta to all component instances
    const constructor = (props) => {
      const component = new ComponentClass()
      Object.assign(component, new ComponentMixin()) // inject internal properties
      Object.keys(props).forEach(prop => {
        if (_.includes(Object.keys(component.props), prop)) { // TODO validate props type
          component[prop] = props[prop] // observable ???
        }
      })
      return component
    }
    constructor.prototype.constructor = ComponentClass
    return constructor
  }
}
