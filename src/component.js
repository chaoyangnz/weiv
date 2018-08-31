// @flow
import _ from 'lodash'
import debug from 'debug'
import VDOM from 'virtual-dom'
import { EventEmitter } from 'fbemitter'
import { autorun } from 'mobx'
// import { createViewModel } from 'mobx-utils'
import { parse } from './template'
import * as weiv from '.'

const log = debug('weiv:render')

export type Prop = {
  type: string,
  default: any,
  required: boolean,
  description: ?string
}

export type Recipe = {
  name: string,
  template?: string,
  props?: {[string]: Prop},
  events?: {[string]: any},
  components: any
}

// default render logic
export function render(component, props: any = {}, events = {}, plugs = {}) {
  console.groupCollapsed('%cRender component: %o', 'color: white; background-color: forestgreen', component)
  // props
  Object.keys(props).forEach(prop => {
    if (_.includes(Object.keys(component.$props), prop)) { // TODO validate props type
      const value = props[prop] // never clone as vue and angular do!!
      Object.defineProperty(component, prop, { value: value, configurable: true, writable: false })
    }
  })
  // events
  component.__emitter__.removeAllListeners()
  Object.keys(events).forEach(event => {
    if (_.includes(Object.keys(component.$events), event)) { // TODO validate props type
      on(component, event, events[event])
    }
  })
  // plugs to fill the slots
  Object.keys(plugs).forEach(slotName => {
    if (component.$slots.has(slotName)) {
      component.__plugs__.set(slotName, plugs[slotName])
    } else {
      console.warn('Fail to find slot %s in component %o template', slotName, component)
    }
  })

  const vdom = component.$ast.render(component, scope(component))
  console.groupEnd()
  return vdom
}

/**
 * When register component in current component or globaly by weiv.component(..),
 * you put decoreated class to the Map, but it will be stored as undecoreated class
 * @param {*} component component itself or its __proto__
 * @param {*} name
 */
export function lookupComponent(component, tag) {
  let componentClass = component.$components[tag]
  if (componentClass) return componentClass
  return weiv.component(tag).$$
}

/**
 * @param {*} component component itself or its __proto__
 * @param {*} name
 */
export function lookupDirective(component, name) {
  let directive = component.$directives[name]
  if (directive) return directive
  return weiv.directive(name)
}

// filter out private properties starting from $, keep user perperties for eval host
export function scope(component) {
  // TODO
  return component
}

function on(component, event, listener) {
  if (_.includes(Object.keys(component.$events), event)) { // TODO validate events type
    component.__emitter__.addListener(event, listener)
  }
}

function $emit(event, ...args) {
  if (_.includes(Object.keys(this.$events), event)) { // TODO validate events type
    this.__emitter__.emit(event, ...args)
  } else {
    throw new Error(`No event '${event}' declaration in component: ${Object.getPrototypeOf(this).constructor.name}`)
  }
}

function $mount(el) {
  if (this.__host__ !== null) {
    throw new Error('Mount a child component is disallowed')
  }
  const tick = () => { // tick
    const vdom = this.__vdom__ // old vdom tree
    log('Before: %o', vdom)
    this.__vdom__ = render(this)
    log('After: %o', this.__vdom__)
    console.assert(vdom !== this.__vdom__)
    if (vdom) {
      const patches = VDOM.diff(vdom, this.__vdom__)
      log('Diff: %o', patches)
      this.__dom__ = VDOM.patch(this.__dom__, patches)
    } else {
      const dom: any = VDOM.create(this.__vdom__)
      this.__dom__ = dom
      const mountNode = document.getElementById(el.substr(1))
      if (!mountNode) {
        throw new Error('Cannot find DOM element: ' + el)
      }
      mountNode.appendChild(dom)
    }
    log('After patch to DOM: %o', self.__dom__)
  }
  autorun(tick)
}

// mix component prototype
function mixinPrototype(componentClass, recipe: Recipe) {
  // populate properties from recipe
  Object.defineProperty(componentClass.prototype, '$name', { value: _.cloneDeep(recipe.name || null) })
  Object.defineProperty(componentClass.prototype, '$props', { value: _.cloneDeep(recipe.props || {}) })
  Object.defineProperty(componentClass.prototype, '$events', { value: _.cloneDeep(recipe.events || {}) })
  Object.defineProperty(componentClass.prototype, '$components', { value: _.mapValues(recipe.components || {}, componentClass => componentClass.$$)})
  Object.defineProperty(componentClass.prototype, '$directives', { value: _.cloneDeep(recipe.directives || []) })
  // attach methods
  Object.defineProperty(componentClass.prototype, '$emit', { value: $emit })
  Object.defineProperty(componentClass.prototype, '$mount', { value: $mount })

  // attach parsed ast to component prototype
  const template = recipe.template ? recipe.template.trim() : ''
  Object.defineProperty(componentClass.prototype, '$slots', { value: new Set() }) // will populate when parsing
  Object.defineProperty(componentClass.prototype, '$ast', { value: Object.freeze(parse(template, componentClass)) })
  Object.freeze(componentClass.prototype)
}

// mixin component instance
function mixinComponent(component, id, host) {
  Object.defineProperty(component, '__id__', { value: id })
  Object.defineProperty(component, '__components__', { value: new Map() })
  if (host) {
    host.__components__.set(id, component)
    Object.defineProperty(component, '__host__', { value: host })
    Object.defineProperty(component, '__root__', { value: host.$root })
  } else {
    Object.defineProperty(component, '__host__', { value: null })
    Object.defineProperty(component, '__root__', { value: component })
  }
  Object.defineProperty(component, '__emitter__', { value: new EventEmitter() })
  // <string, array<vnode>>slots save the vdom rendered in parent scope
  const plugs = new Map()
  component.$slots.forEach(slot => plugs.set(slot, []))
  Object.defineProperty(component, '__plugs__', { value: plugs })
  // Object.defineProperty(component, '__vdom__', { value: null, writable: true })
  // Object.defineProperty(component, '__dom__', { value: null, writable: true })
}

/**
 * IMPORTANT:
 * - All classes in parser, AST and component registry (in component or globally) are orignal UNDECORATED classes.
 * - DECOREATED class is required only when you need to initialise the component instance, but you have rare opportunity to do so.
 */
export function Component(recipe: Recipe) {
  return function decorator(ComponentClass: any) {
    const uniqueid = () => {
      return `${ComponentClass.name}@${Math.random().toString(36).substr(2, 9)}`
    }
    mixinPrototype(ComponentClass, recipe)
    Object.defineProperty(ComponentClass, '$uniqueid', { value: uniqueid })
    // decorated class
    function WeivComponent(id: string, host: any) {
      let component = new ComponentClass()
      mixinComponent(component, id || uniqueid(), host) // inject internal component properties
      // log('%cNew Component: %o', 'color: white; background-color: forestgreen', component)
      return component
    }
    // mutual references of docorated class and undecorated class
    Object.defineProperty(WeivComponent, '$$', { value: ComponentClass })
    Object.defineProperty(ComponentClass, '$$', { value: WeivComponent })
    return WeivComponent
  }
}
