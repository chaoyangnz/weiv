import _ from 'lodash';
import { Block, Component, Expression } from './template/ast';
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

  initialised({contextComponent, scope, block}) { }

  // only component block
  eventsPrepared({contextComponent, scope, block, events}) { }

  propertiesPopulated({contextComponent, scope, block, properties}) { }

  childrenRendered({contextComponent, scope, block, properties, children}) { }

  // only component block
  childComponentCreated({contextComponent, scope, block, properties, children, childComponent}) { }
}

export class IfDirective extends Directive {

  initialised({contextComponent, scope, block}) {
    const value = this.expression.eval(contextComponent, scope)
    block.$ifValue = Boolean(value)
    if (!value) return []
  }
}

export class ElifDirective extends Directive {

  initialised({contextComponent, scope, block}) {
    const value = this.expression.eval(contextComponent, scope)
    block.$ifValue = Boolean(value)

    if (block.parent === null) {
      throw new Error('Cannot use `elif` on root block')
    }
    const ifIndex = _.findLastIndex(block.parent.children, child => _.some(child.directives, directive => directive instanceof IfDirective))
    if (ifIndex === -1) {
      throw new Error('Missing sibling `if` directives')
    }
    const elifIndex = _.findIndex(block.parent.children, child => child === block)
    for (let i = ifIndex; i < elifIndex; ++i) {
      if (_.some(block.parent.children[i].directives, directive => directive instanceof IfDirective || directive instanceof ElifDirective)) {
        if (block.parent.children[i].$ifValue) {
          return []
        }
      }
    }

    if (!value) return []
  }
}

export class ElseDirective extends Directive {

  initialised({contextComponent, scope, block}) {
    if (block.parent === null) {
      throw new Error('Cannot use `else` on root block')
    }
    const ifIndex = _.findLastIndex(block.parent.children, child => _.some(child.directives, directive => directive instanceof IfDirective))
    if (ifIndex === -1) {
      throw new Error('Missing sibling `if` directives')
    }
    const elseIndex = _.findIndex(block.parent.children, child => child === block)
    for (let i = ifIndex; i < elseIndex; ++i) {
      const children = block.parent.children[i]
      if (_.some(children.directives, directive => directive instanceof IfDirective || directive instanceof ElifDirective)) {
        if (block.parent.children[i].$ifValue) {
          return []
        }
      }
    }
  }
}

export class BindDirective extends Directive {

  propertiesPopulated({contextComponent, scope, block, properties}) {
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

  eventsPrepared({contextComponent, scope, block, events}) {
    const value = this.expression.eval(contextComponent, scope)
    if (block instanceof Component) {
      events[this.target] = value
    }
  }

  propertiesPopulated({contextComponent, scope, block, properties}) {
    const value = this.expression.eval(contextComponent, scope)
    if (block instanceof Block && _.includes(HTML_EVENT_ATTRIBUTES, `on${this.target}`)) {
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

  initialised({contextComponent, scope, block}) {
    const value = this.expression.eval(contextComponent, scope)

    if (!block.parent) {
      console.warn('Cannot apply for directive in root block')
      return
    }
    if (!_.isArrayLike(value)) return

    const vnodes = []
    value.forEach((item, i) => {
      const clonedNode = _.clone(block) // can optimise, because i just change directives
      clonedNode.directives = _.clone(block.directives)
      if (clonedNode instanceof Component) {
        // generate new component id
        clonedNode.componentId = block.componentId + '@' + i
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

  propertiesPopulated({contextComponent, scope, block, properties}) {
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

  propertiesPopulated({contextComponent, scope, block, properties}) {
    const value = this.expression.eval(contextComponent, scope)
    properties.innerHTML = String(value)
  }
}

export class ModelDirective extends Directive {

  propertiesPopulated({contextComponent, scope, block, properties}) {
    if (this.expression.ast.type !== 'Identifier') {
      throw new Error('Model supports identifier expression only')
    }
    // disallow observable
    const segs = this.expression.exp.split('.')
    let o = contextComponent
    if (segs.length > 1) {
      o = contextComponent[segs.slice(0, segs.length - 1).join('.')]
    }
    if (isObservable(o, segs[segs.length - 1])) {
      throw new Error('Model must be not observable to avoid two-way data flow')
    }

    const value = this.expression.eval(contextComponent, scope)
    properties['value'] = value
    properties['oninput'] = (event) => {
      contextComponent[this.expression.exp] = event.target.value
    }
  }
}
