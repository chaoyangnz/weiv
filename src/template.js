import htmlparser from 'htmlparser2'
import vdom from 'virtual-dom'

export function compile(template) {
  const stack = []
  /* eslint no-unused-vars: 0 */
  let root = null

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
  }

  class Directive {
    constructor(command, target, params, value) {
      this.command = command
      this.target = target
      this.params = params
      this.value = new Expression(value)
    }
  }

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
        arr.push(new vdom.VText(m[1].trim()))
        if (m[3]) {
          const textNode = new vdom.VText('')
          textNode.expression = new Expression(m[3].trim())
          arr.push(textNode)
        }
      } else {
        arr.push(new vdom.VText(segs[i].trim()))
      }
    }
    arr.push(segs[segs.length - 1])
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
    const node = vdom.h(tagName, attrs, [])
    node.directives = directives
    stack.push(node)
  // console.log(stack)
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
    // console.log(stack)
    if (node.tagName !== tagName.toUpperCase()) {
      throw new Error('Tags are not closed correctly: ' + tagName)
    }
    stack[stack.length - 1].children.push(node)
  // console.log(stack)
  }
  const parser = new htmlparser.Parser({
    onopentag: onOpenTag,
    ontext: onText,
    onclosetag: onCloseTag
  }, {decodeEntities: true});

  parser.write(template)
  parser.done()

  function render(node, data) {
    if (node instanceof vdom.VText && node.expression) {
      const etext = node.expression.evaluate(data)
      console.log('etext: %o', etext)
      const text = etext ? String(etext) : ''
      node.text = text
      return node
    }
    if (node.children && node.children.length > 0) {
      node.children = node.children.map(child => render(child, data))
    }
    return node
  }

  return function (data) {
    return render(root, data)
  }
}

