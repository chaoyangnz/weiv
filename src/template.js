import htmlparser from 'htmlparser2'
import vdom from 'virtual-dom'
import _ from 'lodash'
import Jexl from 'jexl-sync'

class Expression {
  constructor(exp) {
    this.exp = exp
    this.ast = Jexl.parse(exp)
  }

  eval(data) {
    return Jexl.evaluate(this.ast, data)
  }

  render(data) {
    const val = this.eval(data)
    console.debug('Evaluate expression `%s`: %o', this.exp, val)
    const text = (val !== null && val !== undefined) ? String(val) : ''
    return new vdom.VText(text)
  }
}

class Directive {
  constructor(command, target, params, exp) {
    this.command = command
    this.target = target
    this.params = params
    this.expression = new Expression(exp)
  }

  static isTrue(val) {
    if (val === false || val === null || val === undefined) return false
    return true
  }

  process(vnode, data) {
    if (this.command === 'if') {
      const val = this.expression.eval(data)
      return Directive.isTrue(val) ? vnode : null
    }
    if (this.command === 'bind') {
      const val = this.expression.eval(data)
      vnode.properties[this.target] = val
      return vnode
    }
    console.error('Illegal directive: %o', this)
    return vnode
  }
}

class Text {
  constructor(text) {
    this.text = text
  }

  render(data) {
    return new vdom.VText(this.text)
  }
}
class Node {
  constructor(tagName, attributes, directives, children) {
    this.tagName = tagName.toUpperCase()
    this.attributes = attributes || {}
    this.directives = directives || []
    this.children = children || []
  }

  render(data) {
    const attributes = _.cloneDeep(this.attributes)
    const children = _.remove(this.children.map(child => child.render(data)), null)
    let vnode = vdom.h(this.tagName, attributes, children)
    for (let directive of this.directives) {
      vnode = directive.process(vnode, data)
      if (vnode === null) break
    }
    return vnode
  }
}

export function compile(template) {
  const stack = []
  /* eslint no-unused-vars: 0 */
  let root = null

  function parseDirective(name, exp) {
    const pattern = /@(\w+)(:(\w+)(\.\w+)?)?/
    const m = name.match(pattern)
    if (m) {
      return new Directive(m[1], m[3], m[5], exp)
    }
    console.warn('Illagal directive attribute: %s', name)
    return null
  }

  function parseText(text) {
    const arr = []
    const pattern = /(.*)({{([^{}]+))+$/
    const segs = text.split('}}')
    for (let i = 0; i < segs.length - 1; i += 1) {
      const m = segs[i].match(pattern)
      if (m) {
        arr.push(new Text(m[1]))
        if (m[3]) {
          arr.push(new Expression(m[3]))
        }
      } else {
        arr.push(new Text(segs[i]))
      }
    }
    arr.push(new Text(segs[segs.length - 1]))
    return arr
  }

  function onOpenTag(tagName, attributes) {
    console.debug(`<${tagName}>`)
    console.debug(attributes)
    const attrs = {}
    const directives = []
    for (const name of Object.keys(attributes)) {
      if (name.match(/@[^@]+/)) {
        const directive = parseDirective(name, attributes[name])
        if (directive) directives.push(directive)
      } else {
        attrs[name] = attributes[name]
      }
    }
    const node = new Node(tagName, attrs, directives, [])
    stack.push(node)
    console.debug(stack)
  }

  function onText(text) {
    stack[stack.length - 1].children.push(...parseText(text))
  }

  function onCloseTag(tagName) {
    console.debug(`</${tagName}>`)
    if (stack.length === 1) {
      root = stack[0]
      return;
    }
    const node = stack.splice(-1)[0]
    // console.log(node)
    console.debug(stack)
    if (node.tagName !== tagName.toUpperCase()) {
      throw new Error('Tags are not closed correctly: ' + tagName)
    }
    stack[stack.length - 1].children.push(node)
    console.debug(stack)
  }
  const parser = new htmlparser.Parser({
    onopentag: onOpenTag,
    ontext: onText,
    onclosetag: onCloseTag
  }, {decodeEntities: true});

  parser.write(template)
  parser.done()

  return root
}
