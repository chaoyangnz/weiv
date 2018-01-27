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

  initialised({contextComponent, scope}) {
    const value = this.expression.eval(contextComponent, scope)
    if (!value) return []
  }
}

export class BindDirective extends Directive {

  propertiesEvaluated({contextComponent, scope, properties}) {
    const value = this.expression.eval(contextComponent, scope)
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
    for (const item of value) {
      const clonedNode = _.cloneDeep(node) // can optimise, because i just change directives
      _.remove(clonedNode.directives, directive => directive instanceof ForDirective)
      scope[this.target] = item // inject for $var in ..
      vnodes.push(clonedNode.render(contextComponent, scope, {notNewScope: true}))
    }
    return vnodes
  }
}
