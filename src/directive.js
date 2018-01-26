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

  initialised({component, node}) {}

  // only component node
  eventsPrepared({component, node, events}) {}

  propertiesEvaluated({component, node, properties}) {}

  childrenRendered({component, node, properties, children}) {}

  // only component node
  childComponentCreated({component, node, properties, children, childComponent}) {}
}

export class IfDirective extends Directive {

  initialised({component, node}) {
    const value = this.expression.eval(component)
    return !value
  }
}

export class BindDirective extends Directive {

  propertiesEvaluated({component, properties}) {
    const value = this.expression.eval(component)
    properties[this.target] = value
  }
}

export class OnDirective extends Directive {

  eventsPrepared({component, node, events}) {
    const value = this.expression.eval(component)
    if (node instanceof Component) {
      events[this.target] = value
    }
  }

  propertiesEvaluated({component, node, properties}) {
    const value = this.expression.eval(component)
    if (node instanceof Node && _.includes(HTML_EVENT_ATTRIBUTES, `on${this.target}`)) {
      properties[`on${this.target}`] = value
    }
  }
}
