import _ from 'lodash';
import { Node, Component, Expression } from './template/ast';
import { HTML_EVENT_ATTRIBUTES } from './template/html';

export class Directive {
  constructor(command, target, params, exp) {
    this.command = command.toLowerCase()
    this.target = target
    this.params = params
    this.expression = new Expression(exp)
  }

  validate() { return true }

  initialised({contextComponent, scope, node}) { }

  // only component node
  eventsPrepared({contextComponent, scope, node, events}) { }

  propertiesEvaluated({contextComponent, scope, node, properties}) { }

  childrenRendered({contextComponent, scope, node, properties, children}) { }

  // only component node
  childComponentCreated({contextComponent, scope, node, properties, children, childComponent}) { }
}

export class IfDirective extends Directive {

  initialised({contextComponent, scope, node}) {
    const value = this.expression.eval(contextComponent, scope)
    node.$ifValue = Boolean(value)
    if (!value) return []
  }
}

export class ElifDirective extends Directive {

  initialised({contextComponent, scope, node}) {
    const value = this.expression.eval(contextComponent, scope)
    node.$ifValue = Boolean(value)

    if (node.parent === null) {
      throw new Error('Cannot use `elif` on root node')
    }
    const index = _.findIndex(node.parent.children, child => child === node)
    if (index === 0) {
      throw new Error('Missing forward `if or elif` directives')
    }
    for (let i = 0; i < index; ++i) {
      if (_.some(node.parent.children[i].directives, directive => directive instanceof IfDirective || directive instanceof ElifDirective)) {
        if (node.parent.children[i].$ifValue) {
          return []
        }
      }
    }

    if (!value) return []
  }
}

export class ElseDirective extends Directive {

  initialised({contextComponent, scope, node}) {
    if (node.parent === null) {
      throw new Error('Cannot use `else` on root node')
    }
    const index = _.findIndex(node.parent.children, child => child === node)
    if (index === 0) {
      throw new Error('Missing forward `if or elif` directives')
    }
    for (let i = 0; i < index; ++i) {
      if (_.some(node.parent.children[i].directives, directive => directive instanceof IfDirective || directive instanceof ElifDirective)) {
        if (node.parent.children[i].$ifValue) {
          return []
        }
      }
    }
  }
}

export class BindDirective extends Directive {

  propertiesEvaluated({contextComponent, scope, node, properties}) {
    const value = this.expression.eval(contextComponent, scope)
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

  eventsPrepared({contextComponent, scope, node, events}) {
    const value = this.expression.eval(contextComponent, scope)
    if (node instanceof Component) {
      events[this.target] = value
    }
  }

  propertiesEvaluated({contextComponent, scope, node, properties}) {
    const value = this.expression.eval(contextComponent, scope)
    if (node instanceof Node && _.includes(HTML_EVENT_ATTRIBUTES, `on${this.target}`)) {
      properties[`on${this.target}`] = value
    }
  }
}

export class VarDirective extends Directive {

  initialised({contextComponent, scope}) {
    const value = this.expression.eval(contextComponent, scope)
    scope[this.target] = value
  }
}

export class ForDirective extends Directive {

  initialised({contextComponent, scope, node}) {
    const value = this.expression.eval(contextComponent, scope)

    if (!node.parent) {
      console.warn('Cannot apply for directive in root node')
      return
    }
    if (!_.isArrayLike(value)) return

    const vnodes = []
    value.forEach((item, i) => {
      const clonedNode = _.clone(node) // can optimise, because i just change directives
      clonedNode.directives = _.clone(node.directives)
      if (clonedNode instanceof Component) {
        // generate new component id
        clonedNode.componentId = node.componentId + '@' + i
      }
      _.remove(clonedNode.directives, directive => directive instanceof ForDirective)
      scope['$index'] = i
      scope[this.target] = item // inject for $var in ..
      const vnode = clonedNode.render(contextComponent, scope)
      vnode.key = clonedNode.componentId // assign a key for vnode
      vnodes.push(vnode)
    })
    return vnodes
  }
}

export class ShowDirective extends Directive {

  propertiesEvaluated({contextComponent, scope, node, properties}) {
    const value = this.expression.eval(contextComponent, scope)
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

  propertiesEvaluated({contextComponent, scope, node, properties}) {
    const value = this.expression.eval(contextComponent, scope)
    properties.innerHTML = String(value)
  }
}
