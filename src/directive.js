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

  initialised({contextComponent, node}) {}

  // only component node
  eventsPrepared({contextComponent, node, events}) {}

  propertiesEvaluated({contextComponent, node, properties}) {}

  childrenRendered({contextComponent, node, properties, children}) {}

  // only component node
  childComponentCreated({contextComponent, node, properties, children, childComponent}) {}
}

export class IfDirective extends Directive {

  initialised({contextComponent, node}) {
    const value = this.expression.eval(contextComponent)
    return !value
  }
}

export class BindDirective extends Directive {

  propertiesEvaluated({contextComponent, properties}) {
    const value = this.expression.eval(contextComponent)
    properties[this.target] = value
  }
}

export class OnDirective extends Directive {

  eventsPrepared({contextComponent, node, events}) {
    const value = this.expression.eval(contextComponent)
    if (node instanceof Component) {
      events[this.target] = value
    }
  }

  propertiesEvaluated({contextComponent, node, properties}) {
    const value = this.expression.eval(contextComponent)
    if (node instanceof Node && _.includes(HTML_EVENT_ATTRIBUTES, `on${this.target}`)) {
      properties[`on${this.target}`] = value
    }
  }
}
