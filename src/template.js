import htmlparser from 'htmlparser2'
import vdom from 'virtual-dom'

class Expression {
  constructor(value) {
    this.value = value
  }

  evaluate(data) {
    let result = null
    /* eslint no-eval: 0 */
    eval(`with (data) { result = ( ${this.value} ) }`)
    return result
  }

  render(data) {
    const etext = this.evaluate(data)
    console.log('etext: %o', etext)
    const text = (etext !== null && etext !== undefined) ? String(etext) : ''
    return new vdom.VText(text)
  }
}

class Directive {
  constructor(command, target, params, value) {
    this.command = command
    this.target = target
    this.params = params
    this.value = new Expression(value)
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
    return vdom.h(this.tagName, this.attributes, this.children.map(child => child.render(data)))
  }
}

export function compile(template) {
  const stack = []
  /* eslint no-unused-vars: 0 */
  let root = null

  function parseDirective(name, value) {
    const pattern = /@(\w+)(:(\w+)(\.\w+)?)?/
    const m = name.match(pattern)
    if (m) {
      return new Directive(m[1], m[3], m[5], value)
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
        arr.push(new Text(m[1].trim()))
        if (m[3]) {
          arr.push(new Expression(m[3].trim()))
        }
      } else {
        arr.push(new Text(segs[i].trim()))
      }
    }
    arr.push(new Text(segs[segs.length - 1]))
    return arr
  }

  function onOpenTag(tagName, attributes) {
    console.log(`<${tagName}>`)
    console.log(attributes)
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
    console.log(stack)
  }

  function onText(text) {
    stack[stack.length - 1].children.push(...parseText(text))
  }

  function onCloseTag(tagName) {
    console.log(`</${tagName}>`)
    if (stack.length === 1) {
      root = stack[0]
      return;
    }
    const node = stack.splice(-1)[0]
    // console.log(node)
    console.log(stack)
    if (node.tagName !== tagName.toUpperCase()) {
      throw new Error('Tags are not closed correctly: ' + tagName)
    }
    stack[stack.length - 1].children.push(node)
    console.log(stack)
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
