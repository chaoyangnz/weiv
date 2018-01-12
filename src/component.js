// @flow
import { EventEmitter } from 'fbemitter'
import _ from 'lodash'
import { parse } from './template'
import Weiv from './weiv'

export type Prop = {
  type: string,
  default: any,
  required: boolean
}

export type Options = {
  name: string,
  target?: string,
  template?: string,
  props?: {[string]: Prop},
  components: any
}

function mixinPrototype(componentClass, options: Options) {
  Object.defineProperty(componentClass.prototype, '$name', { value: _.cloneDeep(options.name || null) })
  Object.defineProperty(componentClass.prototype, '$target', { value: options.target || null})
  Object.defineProperty(componentClass.prototype, '$props', { value: _.cloneDeep(options.props || {}) })
  Object.defineProperty(componentClass.prototype, '$components', { value: _.cloneDeep(options.components || []) })
  Object.defineProperty(componentClass.prototype, '$render', { value: function (props: any = {}) {
    Object.keys(props).forEach(prop => {
      if (_.includes(Object.keys(this.$props), prop)) { // TODO validate props type
        const value = _.cloneDeep(props[prop])
        Object.freeze(value)
        Object.defineProperty(this, prop, { value: value, configurable: true, writable: false })
      }
    })
    this.$vdom = this.$template.render(this)
  }})
  Object.defineProperty(componentClass.prototype, '$isRoot', { value: function () {
    return !!this.$target
  }})
  Object.defineProperty(componentClass.prototype, '$lookupComponent', { value: function (tag) {
    let componentClass = this.$components[tag]
    if (componentClass) return componentClass
    return Weiv.$components.get(tag)
  }})
  if (options.template) {
    parse(options.template.trim() || '<div />', componentClass)
  }
  Object.freeze(componentClass.prototype)
}

function mixinComponent(component, id, parent) {
  Object.defineProperty(component, '$id', { value: id })
  Object.defineProperty(component, '$children', { value: [] })
  if (parent) {
    parent.$children[id] = component
    Object.defineProperty(component, '$parent', { value: parent })
    Object.defineProperty(component, '$root', { value: parent.$root })
  } else {
    Object.defineProperty(component, '$parent', { value: null })
    Object.defineProperty(component, '$root', { value: component })
  }
  Object.defineProperty(component, '$emitter', { value: new EventEmitter() })
  Object.defineProperty(component, '$vdom', { value: null, writable: true })
  Object.defineProperty(component, '$dom', { value: null, writable: true })
}

export function Component(options: Options) {
  return function decorator(ComponentClass: any) {
    mixinPrototype(ComponentClass, options)

    const constructor = (id: string, parent: any) => {
      const component = new ComponentClass()
      mixinComponent(component, id, parent) // inject internal component properties
      console.info('%cComponent: %o', 'color: red', component)
      return component
    }

    constructor.origin = ComponentClass
    return constructor
  }
}
