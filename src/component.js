// @flow
import _ from 'lodash'
import VDOM from 'virtual-dom'
import { EventEmitter } from 'fbemitter'
import { autorun } from 'mobx'
import { parse } from './template'
import { Weiv } from '.'

export type Prop = {
  type: string,
  default: any,
  required: boolean,
  description: ?string
}

export type Options = {
  name: string,
  template?: string,
  props?: {[string]: Prop},
  events?: {[string]: any},
  components: any
}

function $render(props: any = {}) {
  Object.keys(props).forEach(prop => {
    if (_.includes(Object.keys(this.$props), prop)) { // TODO validate props type
      const value = _.cloneDeep(props[prop])
      Object.freeze(value)
      Object.defineProperty(this, prop, { value: value, configurable: true, writable: false })
    }
  })
  this.$vdom = this.$template.render(this)
}

function $lookupComponent(tag) {
  let componentClass = this.$components[tag]
  if (componentClass) return componentClass
  return Weiv.$components.get(tag)
}

function $on(event, listener) {
  if (_.includes(Object.keys(this.$events), event)) { // TODO validate events type
    this.$emitter.addListener(event, listener)
  }
}

function $emit(event, ...args) {
  if (_.includes(Object.keys(this.$events), event)) { // TODO validate events type
    this.$emitter.emit(event, ...args)
  } else {
    throw new Error(`No event '${event}' declaration in component: ${Object.getPrototypeOf(this).constructor.name}`)
  }
}

function $mount(el) {
  if (this.$parent !== null || this.$dom !== null) {
    throw new Error('Mount a child component is disallowed')
  }
  const tick = () => { // tick
    const vdom = this.$vdom // old vdom tree
    console.info('Before: %o', vdom)
    this.$render()
    console.info('After: %o', this.$vdom)
    console.assert(vdom !== this.$vdom)
    if (vdom) {
      const patches = VDOM.diff(vdom, this.$vdom)
      console.info('Diff: %o', patches)
      this.$dom = VDOM.patch(this.$dom, patches)
    } else {
      const dom: any = VDOM.create(this.$vdom)
      this.$dom = dom
      const mountNode = document.getElementById(el.substr(1))
      if (!mountNode) {
        throw new Error('Cannot find DOM element: ' + el)
      }
      mountNode.appendChild(dom)
    }
    console.info('After patch to DOM: %o', self.$dom)
  }
  autorun(tick)
}

function mixinPrototype(componentClass, options: Options) {
  Object.defineProperty(componentClass.prototype, '$name', { value: _.cloneDeep(options.name || null) })
  Object.defineProperty(componentClass.prototype, '$props', { value: _.cloneDeep(options.props || {}) })
  Object.defineProperty(componentClass.prototype, '$events', { value: _.cloneDeep(options.events || {}) })
  Object.defineProperty(componentClass.prototype, '$components', { value: _.cloneDeep(options.components || []) })
  Object.defineProperty(componentClass.prototype, '$render', { value: $render })
  Object.defineProperty(componentClass.prototype, '$lookupComponent', { value: $lookupComponent })
  Object.defineProperty(componentClass.prototype, '$on', { value: $on })
  Object.defineProperty(componentClass.prototype, '$emit', { value: $emit })
  Object.defineProperty(componentClass.prototype, '$mount', { value: $mount })
  // attach parsed ast to component prototype
  const template = options.template ? options.template.trim() : '<template />'
  Object.defineProperty(componentClass.prototype, '$template', {value: parse(template, componentClass)})
  Object.freeze(componentClass.prototype)

  // static methods
  Object.defineProperty(componentClass, '$uniqueid', { value: function () {
    return `${componentClass.name}@${Math.random().toString(36).substr(2, 9)}`
  }})
}

function mixinComponent(component, id, parent) {
  Object.defineProperty(component, '$id', { value: id })
  Object.defineProperty(component, '$children', { value: new Map() })
  if (parent) {
    parent.$children.set(id, component)
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

    const Component = (id: string, parent: any) => {
      const component = new ComponentClass()
      mixinComponent(component, id || ComponentClass.$uniqueid(), parent) // inject internal component properties
      console.info('%cComponent: %o', 'color: red', component)
      return component
    }
    Object.defineProperty(Component, '$original', { value: ComponentClass })
    return Component
  }
}
