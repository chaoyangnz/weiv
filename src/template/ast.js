import _ from 'lodash'
import VDOM, { VNode } from 'virtual-dom'
import Jexl from 'jexl-sync'
// @flow

import debug from 'debug'
import { HTML_EVENT_ATTRIBUTES, HTML_GLOBAL_ATTRIBUTES, HTML_TAG_ATTRIBUTES } from './html'
import * as utils from '../utils'

const log = debug('weiv:render')

interface Renderer {
  render(contextComponent: any, superScope: any): VNode
}

// Expression can exist as child of Node, also as the value of attribute
export class Expression implements Renderer {
  constructor(exp) {
    this.exp = exp
    this.ast = Jexl.parse(exp)
  }

  eval(contextComponent, scope) {
    let val = Jexl.evaluate(this.ast, scope)

    log('Evaluate expression `%s`: %o', this.exp, val)
    // autobind functions
    if (val && typeof val === 'function') {
      val = val.bind(contextComponent)
    }
    return val
  }

  @utils.log
  render(contextComponent, scope) {
    const val = this.eval(contextComponent, scope)
    const text = (val !== null && val !== undefined) ? String(val) : ''
    return new VDOM.VText(text)
  }
}

export class Text implements Renderer {
  constructor(text) {
    this.text = text
  }

  render(contextComponent, scope) {
    console.log('%o', this)
    return new VDOM.VText(this.text)
  }
}

export class Element implements Renderer {
  constructor(contextComponentClass, tagName, attributes, parse = true) {
    this.contextComponentClass = contextComponentClass
    this.tagName = tagName
    this.attributes = {} // name -> value (string), except html events: onclick -> value (expression)
    this.directives = [] // @command:(target).(params..) -> expression
    this.children = [] // children elements/texts
    this.parent = null
    if (parse) {
      this._parseAttributesAndDirectives(attributes)
    }
  }

  _parseAttributesAndDirectives(attributes) {
    for (let name of Object.keys(attributes)) {
      if (name.match(/@[^@]+/)) { // directive prefix: @
        const directive = this._parseDirective(name, attributes[name])
        if (directive) this.directives.push(directive)
      } else if (_.includes(HTML_EVENT_ATTRIBUTES, name)) {
        this.attributes[name] = new Expression(attributes[name])
      } else if (_.includes(HTML_GLOBAL_ATTRIBUTES, name) || _.includes(HTML_TAG_ATTRIBUTES[name], this.tagName)) {
        this.attributes[name] = attributes[name]
      } else {
        console.warn('Illegal attribute `%s` for tag `%s`', name, this.tagName)
      }
    }
  }

  _parseDirective(name, exp) {
    const pattern = /@(\w+)(:(\w+)((\.\w+)*))?/
    const m = name.match(pattern)
    if (m) {
      let params = []
      if (m[4]) {
        params = _.remove(m[4].split('.'), null)
      }
      const directiveClass = this.contextComponentClass.prototype.$lookupDirective(m[1])
      if (directiveClass) {
        const directive = new directiveClass(m[1], m[3], params, exp)
        if (directive.validate()) return directive
      }
    }
    throw new Error(`Illagal directive attribute format: ${name}`)
  }

  closestComponent() {
    let element = this
    while (element != null) {
      /* eslint no-use-before-define: 0*/
      if (element instanceof CustomElement) return element
      element = element.parent
    }
    return null
  }

  previousSiblingNode() {
    if (this.parent === null) return null
    const index = _.indexOf(this.parent.children, this)
    if (index === 0) return null
    return this.parent.children[index - 1]
  }

  nextSiblingNode() {
    if (this.parent === null) return null
    const index = _.indexOf(this.parent.children, this)
    if (index === this.parent.children.length - 1) return null
    return this.parent.children[index + 1]
  }

  // true -> continue  array -> stop
  _process(results) {
    for (const result of results) {
      if (_.isArray(result)) return result
    }
    return true
  }

  @utils.log(false)
  render(contextComponent, superScope) {
    const scope = {$super: superScope}

    let result = this._process(this.directives.map(directive => directive.initialised({contextComponent, scope, element: this})))
    if (result !== true) return result

    // only `onclick..` attributes is expression
    let properties = { attributes: {} }
    _.forIn(this.attributes, (attr, name) => {
      if (attr instanceof Expression) { // events: onclick...
        properties[name] = attr.eval(contextComponent, scope)
      } else { // attributes
        properties.attributes[name] = attr
      }
    })

    // let properties = _.mapValues(this.attributes, prop => prop instanceof Expression ? prop.eval(contextComponent, scope) : prop)

    result = this._process(this.directives.map(directive => directive.propertiesPopulated({contextComponent, scope, element: this, properties})))
    if (result !== true) return result

    const children = _.compact(_.flatMap(this.children, child => child.render(contextComponent, scope)))

    result = this._process(this.directives.map(directive => directive.childrenRendered({contextComponent, scope, element: this, properties, children})))
    if (result !== true) return result

    return VDOM.h(this.tagName, properties, children)
  }
}

/**
 * <custom-tag>
 *  <p slot="slot">...</p>
 * </custom-tag>
 */
export class CustomElement extends Element {
  constructor(contextComponentClass, tagName, attributes, componentClass) {
    super(contextComponentClass, tagName, attributes, false)
    this.componentClass = componentClass
    this.componentId = componentClass.$uniqueid()
    this.attributes = {}
    this.directives = []
    for (let name of Object.keys(attributes)) {
      if (name.match(/@[^@]+/)) { // directive prefix: @
        const directive = super._parseDirective(name, attributes[name])
        if (directive) this.directives.push(directive)
      } else {
        // validate component props
        if (_.includes(Object.keys(componentClass.prototype.$props), name)) {
          this.attributes[name] = attributes[name]
        } else {
          console.warn('Illegal commponent props %s in %s', name, componentClass.name)
        }
      }
    }
  }

  @utils.log(false)
  render(contextComponent, superScope) {
    const scope = {$super: superScope}

    let result = this._process(this.directives.map(directive => directive.initialised({contextComponent, scope, element: this})))
    if (result !== true) return result

    const events = {}

    result = this._process(this.directives.map(directive => directive.eventsPrepared({contextComponent, scope, element: this, events})))
    if (result !== true) return result

    let properties = _.mapValues(this.attributes, prop => prop instanceof Expression ? prop.eval(contextComponent, scope) : prop)

    result = this._process(this.directives.map(directive => directive.propertiesPopulated({contextComponent, scope, element: this, properties})))
    if (result !== true) return result

    const children = _.compact(_.flatMap(this.children, child => child.render(contextComponent, scope)))

    result = this._process(this.directives.map(directive => directive.childrenRendered({contextComponent, scope, element: this, properties, children})))
    if (result !== true) return result

    /* eslint new-cap: 0 */
    let component = contextComponent.__components__.get(this.componentId)
    if (!component) {
      log('New')
      component = new this.componentClass.$$(this.componentId, contextComponent)
    }

    result = this._process(this.directives.map(directive => directive.componentPrepared({contextComponent, scope, element: this, properties, children, component})))
    if (result !== true) return result

    // process childrent to fill slots
    const plugs = {}
    children.forEach(child => {
      const slotName = _.has(child.properties, 'slot') ? child.properties['slot'] : 'default'
      if (component.$slots.has(slotName)) {
        const slot = plugs[slotName] || []
        slot.push(child)
        plugs[slotName] = slot
      } else {// otherwise ignore
        console.warn('Fail to find slot %s in component %s template', slotName, this.componentClass.name)
      }
    })

    component.$render(properties, events, plugs)
    component.__vdom__.properties.id = this.componentId // attach an id attribute

    return component.__vdom__
  }
}

/**
 * <slot name="xx"></slot>
 */
export class Slot extends Element {
  constructor(contextComponentClass, tagName, attributes) {
    super(contextComponentClass, tagName, attributes)
    this.name = attributes.name || 'default'
  }

  @utils.log(false)
  render(contextComponent, superScope) { // return multiple vnodes
    const scope = {$super: superScope}

    let result = this._process(this.directives.map(directive => directive.initialised({contextComponent, scope, element: this})))
    if (result !== true) return result

    let properties = {} // ignore any attributes

    result = this._process(this.directives.map(directive => directive.propertiesPopulated({contextComponent, scope, element: this, properties})))
    if (result !== true) return result

    // NOT support slot's children. Never render them if you write
    const children = [] // _.compact(_.flatMap(this.children, child => child.render(contextComponent, scope)))

    result = this._process(this.directives.map(directive => directive.childrenRendered({contextComponent, scope, element: this, properties, children})))
    if (result !== true) return result

    if (contextComponent.__plugs__.has(this.name) && !_.isEmpty(contextComponent.$vslots.get(this.name))) {
      return contextComponent.__plugs__.get(this.name)
    }

    return children
  }
}
