import _ from 'lodash';
import { Element, CustomElement, Expression } from './template/ast';
import { HTML_EVENT_ATTRIBUTES } from './template/html';
import { isObservable } from 'mobx';

export class Directive {
  constructor(command, target, params, exp) {
    this.command = command.toLowerCase()
    this.target = target
    this.params = params
    this.expression = new Expression(exp)
  }

  validate() { return true }

  initialised({hostComponent, scope, element}) { }

  // only component element
  eventsPrepared({hostComponent, scope, element, events}) { }

  propertiesPopulated({hostComponent, scope, element, properties}) { }

  childrenRendered({hostComponent, scope, element, properties, children}) { }

  // only component element
  componentPrepared({hostComponent, scope, element, properties, children, childComponent}) { }
}

export class IfDirective extends Directive {

  initialised({hostComponent, scope, element}) {
    const value = this.expression.eval(hostComponent, scope)
    element.$ifValue = Boolean(value)
    if (!value) return []
  }
}

export class ElifDirective extends Directive {

  initialised({hostComponent, scope, element}) {
    const value = this.expression.eval(hostComponent, scope)
    element.$ifValue = Boolean(value)

    if (element.parent === null) {
      throw new Error('Cannot use `elif` on root element')
    }
    const ifIndex = _.findLastIndex(element.parent.children, child => _.some(child.directives, directive => directive instanceof IfDirective))
    if (ifIndex === -1) {
      throw new Error('Missing sibling `if` directives')
    }
    const elifIndex = _.findIndex(element.parent.children, child => child === element)
    for (let i = ifIndex; i < elifIndex; ++i) {
      if (_.some(element.parent.children[i].directives, directive => directive instanceof IfDirective || directive instanceof ElifDirective)) {
        if (element.parent.children[i].$ifValue) {
          return []
        }
      }
    }

    if (!value) return []
  }
}

export class ElseDirective extends Directive {

  initialised({hostComponent, scope, element}) {
    if (element.parent === null) {
      throw new Error('Cannot use `else` on root element')
    }
    const ifIndex = _.findLastIndex(element.parent.children, child => _.some(child.directives, directive => directive instanceof IfDirective))
    if (ifIndex === -1) {
      throw new Error('Missing sibling `if` directives')
    }
    const elseIndex = _.findIndex(element.parent.children, child => child === element)
    for (let i = ifIndex; i < elseIndex; ++i) {
      const children = element.parent.children[i]
      if (_.some(children.directives, directive => directive instanceof IfDirective || directive instanceof ElifDirective)) {
        if (element.parent.children[i].$ifValue) {
          return []
        }
      }
    }
  }
}

export class BindDirective extends Directive {

  propertiesPopulated({hostComponent, scope, element, properties}) {
    const value = this.expression.eval(hostComponent, scope)
    if (this.target === 'class') {
      const classes = []
      _.forIn(value, (val, key) => {
        if (val) classes.push(key)
      })
      properties['className'] = classes.join(' ')
      return
    }

    properties[this.target] = value
  }
}

export class OnDirective extends Directive {

  eventsPrepared({hostComponent, scope, element, events}) {
    const value = this.expression.eval(hostComponent, scope)
    if (element instanceof CustomElement) {
      events[this.target] = value
    }
  }

  propertiesPopulated({hostComponent, scope, element, properties}) {
    const value = this.expression.eval(hostComponent, scope)
    if (element instanceof Element && _.includes(HTML_EVENT_ATTRIBUTES, `on${this.target}`)) {
      properties[`on${this.target}`] = value
    }
  }
}

export class VarDirective extends Directive {

  initialised({hostComponent, scope}) {
    const value = this.expression.eval(hostComponent, scope)
    scope[this.target] = value
  }
}

export class ForDirective extends Directive {

  initialised({hostComponent, scope, element}) {
    const value = this.expression.eval(hostComponent, scope)

    if (!element.parent) {
      console.warn('Cannot apply for directive in root element')
      return
    }
    if (!_.isArrayLike(value)) return

    const vnodes = []
    value.forEach((item, i) => {
      const clonedNode = _.clone(element) // can optimise, because i just change directives
      clonedNode.directives = _.clone(element.directives)
      if (clonedNode instanceof CustomElement) {
        // generate new component id
        clonedNode.componentId = element.componentId + '@' + i
      }
      _.remove(clonedNode.directives, directive => directive instanceof ForDirective)
      scope['$index'] = i
      scope[this.target] = item // inject for $var in ..
      const vnode = clonedNode.render(hostComponent, scope)
      vnode.key = clonedNode.componentId // assign a key for vnode
      vnodes.push(vnode)
    })
    return vnodes
  }
}

export class ShowDirective extends Directive {

  propertiesPopulated({hostComponent, scope, element, properties}) {
    const value = this.expression.eval(hostComponent, scope)
    if (value) {
      if (Object.hasOwnProperty(properties, 'style')) {
        delete properties.style.display
      }
    } else {
      properties.style = properties.style || {}
      properties.style.display = 'none'
    }
  }
}

export class HtmlDirective extends Directive {

  propertiesPopulated({hostComponent, scope, element, properties}) {
    const value = this.expression.eval(hostComponent, scope)
    properties.innerHTML = String(value)
  }
}

export class ModelDirective extends Directive {

  propertiesPopulated({hostComponent, scope, element, properties}) {
    if (this.expression.ast.type !== 'Identifier') {
      throw new Error('Model supports identifier expression only')
    }
    // disallow observable
    const segs = this.expression.exp.split('.')
    let o = hostComponent
    for (let i = 0; i < segs.length - 1; ++i) {
      o = o[segs[i]]
    }
    if (isObservable(o, segs[segs.length - 1])) {
      throw new Error('Model must be not observable to avoid two-way data flow')
    }

    const value = this.expression.eval(hostComponent, scope)
    properties['value'] = value
    properties['oninput'] = (event) => {
      hostComponent[this.expression.exp] = event.target.value
    }
  }
}
