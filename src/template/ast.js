import _ from 'lodash'
import vdom from 'virtual-dom'
import Jexl from 'jexl-sync'
import { HTML_EVENT_ATTRIBUTES } from './html'

export class Expression {
  constructor(exp) {
    this.exp = exp
    this.ast = Jexl.parse(exp)
  }

  eval(component) {
    let val = Jexl.evaluate(this.ast, component)
    console.debug('Evaluate expression `%s`: %o', this.exp, val)
    // autobind functions
    if (val && typeof val === 'function') {
      val = val.bind(component)
    }
    return val
  }

  render(component) {
    const val = this.eval(component)
    const text = (val !== null && val !== undefined) ? String(val) : ''
    return new vdom.VText(text)
  }
}

const STRUCTRUAL_DIRECTIVES = [
  'if',
  'elseif',
  'else'
]

const BEHAVIORAL_DIRECTIVES = [
  'bind',
  'on'
]

const STRUCTRUAL_DIRECTIVE = 0
const BEHAVIORAL_DIRECTIVE = 1

class Directive {
  constructor(command, target, params, exp) {
    this.command = command.toLowerCase()
    this.target = target
    this.params = params
    this.expression = new Expression(exp)
    if (_.includes(STRUCTRUAL_DIRECTIVES, this.command)) {
      this.type = STRUCTRUAL_DIRECTIVE
    } else if (_.includes(BEHAVIORAL_DIRECTIVES, this.command)) {
      this.type = BEHAVIORAL_DIRECTIVE
    } else {
      throw new Error(`Illegal directive: '${this.command}'`)
    }
  }

  static isTrue(val) {
    if (val === false || val === null || val === undefined) return false
    return true
  }
}

export class Text {
  constructor(text) {
    this.text = text
  }

  render(component) {
    return new vdom.VText(this.text)
  }
}

function parseDirective(name, exp) {
  const pattern = /@(\w+)(:(\w+)((\.\w+)*))?/
  const m = name.match(pattern)
  if (m) {
    let params = []
    if (m[4]) {
      params = _.remove(m[4].split('.'), null)
    }
    return new Directive(m[1], m[3], params, exp)
  }
  throw new Error(`Illagal directive attribute format: ${name}`)
}

export class Node {
  constructor(tagName, attributes) {
    this.tagName = tagName.toLowerCase()
    this.properties = {}
    this.directives = []
    this.children = []
    for (let name of Object.keys(attributes)) {
      if (name.match(/@[^@]+/)) { // directive prefix: @
        const directive = parseDirective(name, attributes[name])
        if (directive) this.directives.push(directive)
      } else if (_.includes(HTML_EVENT_ATTRIBUTES, name.toLowerCase())) {
        this.properties[name] = new Expression(attributes[name])
      } else {
        this.properties[name] = attributes[name]
      }
    }
  }

  // structural directive
  structural(directive, properties, children, component) {
    const val = directive.expression.eval(component)
    if (directive.command === 'if') {
      return Directive.isTrue(val)
    }
    return true
  }

  // behavioral directive
  behavioral(directive, properties, children, component) {
    const val = directive.expression.eval(component)
    if (directive.command === 'bind') {
      properties[directive.target] = val
    } else if (directive.command === 'on') {
      if (val && typeof val === 'function') {
        if (_.includes(HTML_EVENT_ATTRIBUTES, 'on' + directive.target.toLowerCase())) {
          properties[`on${directive.target}`] = val
        }
      }
    }
  }

  render(component) {
    let properties = _.cloneDeep(this.properties)
    // only `onclick..` attributes is expression
    properties = _.mapValues(properties, attr => attr instanceof Expression ? attr.eval(component) : attr)
    const children = _.remove(this.children.map(child => child.render(component)), null)
    // start directiv processing
    const structualDirectives = this.directives.filter(directive => directive.type === STRUCTRUAL_DIRECTIVE)
    const behavioralDirectives = this.directives.filter(directive => directive.type === BEHAVIORAL_DIRECTIVE)
    for (let directive of structualDirectives) {
      if (!this.structural(directive, properties, children, component)) return null
    }
    for (let directive of behavioralDirectives) {
      this.behavioral(directive, properties, children, component)
    }
    return vdom.h(this.tagName, properties, children)
  }
}

export class Component {
  constructor(tagName, attributes, componentClass) {
    this.tagName = tagName.toLowerCase()
    this.properties = {}
    this.directives = []
    this.children = []
    this.componentClass = componentClass
    this.componentId = componentClass.$uniqueid()
    for (let name of Object.keys(attributes)) {
      if (name.match(/@[^@]+/)) { // directive prefix: @
        const directive = parseDirective(name, attributes[name])
        if (directive) this.directives.push(directive)
      } else {
        // validate component props
        if (_.includes(Object.keys(componentClass.prototype.$props), name)) {
          this.properties[name] = attributes[name]
        } else {
          console.warn('Illegal commponent props %s in %s', name, componentClass.$class.name)
        }
      }
    }
  }

  // structural directive
  structural(directive, properties, children, component) {
    if (directive.command === 'if') {
      const val = directive.expression.eval(component)
      return Directive.isTrue(val)
    }
    return true
  }

  // behavioral directive
  behavioral(directive, properties, children, component, childComponent) {
    const val = directive.expression.eval(component)
    if (directive.command === 'bind') {
      properties[directive.target] = val
    } else if (directive.command === 'on') {
      if (val && typeof val === 'function') {
        if (_.includes(directive.params, 'native')) {
          if (_.includes(HTML_EVENT_ATTRIBUTES, directive.target.toLowerCase())) {
            // TODO add native event to component's root dom element
          }
        } else {
          childComponent.$addEventListener(directive.target, val)
        }
      }
    } else {
      console.error('Illegal directive: %o', directive)
    }
  }

  render(component) {
    let properties = _.cloneDeep(this.properties)
    // only `onclick..` attributes is expression
    properties = _.mapValues(properties, attr => attr instanceof Expression ? attr.eval(component) : attr)
    const children = _.remove(this.children.map(child => child.render(component)), null)
    // start directiv processing
    const structualDirectives = this.directives.filter(directive => directive.type === STRUCTRUAL_DIRECTIVE)
    const behavioralDirectives = this.directives.filter(directive => directive.type === BEHAVIORAL_DIRECTIVE)
    for (let directive of structualDirectives) {
      if (!this.structural(directive, properties, children, component)) return null
    }
    /* eslint new-cap: 0 */
    let childComponent = component.$children[this.componentId]
    if (!childComponent) {
      childComponent = new this['componentClass'](this.componentId, component)
    }
    childComponent.$emitter.removeAllListeners()
    for (let directive of behavioralDirectives) {
      this.behavioral(directive, properties, children, component, childComponent)
    }
    childComponent.$render(properties)
    return childComponent.$vdom
  }
}
