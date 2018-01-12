import htmlparser from 'htmlparser2'
import vdom from 'virtual-dom'
import _ from 'lodash'
import Jexl from 'jexl-sync'

const HTML_TAGS = [
  'a',
  'abbr',
  'acronym',
  'address',
  'applet',
  'area',
  'article',
  'aside',
  'audio',
  'b',
  'base',
  'basefont',
  'bdi',
  'bdo',
  'big',
  'blockquote',
  'body',
  'br',
  'button',
  'canvas',
  'caption',
  'center',
  'cite',
  'code',
  'col',
  'colgroup',
  'datalist',
  'dd',
  'del',
  'details',
  'dfn',
  'dialog',
  'dir',
  'div',
  'dl',
  'dt',
  'em',
  'embed',
  'fieldset',
  'figcaption',
  'figure',
  'font',
  'footer',
  'form',
  'frame',
  'frameset',
  'h1',
  'head',
  'header',
  'hr',
  'html',
  'i',
  'iframe',
  'img',
  'input',
  'ins',
  'kbd',
  'label',
  'legend',
  'li',
  'link',
  'main',
  'map',
  'mark',
  'menu',
  'menuitem',
  'meta',
  'meter',
  'nav',
  'noframes',
  'noscript',
  'object',
  'ol',
  'optgroup',
  'option',
  'output',
  'p',
  'param',
  'picture',
  'pre',
  'progress',
  'q',
  'rp',
  'rt',
  'ruby',
  's',
  'samp',
  'script',
  'section',
  'select',
  'small',
  'source',
  'span',
  'strike',
  'strong',
  'style',
  'sub',
  'summary',
  'sup',
  'table',
  'tbody',
  'td',
  'textarea',
  'tfoot',
  'th',
  'thead',
  'time',
  'title',
  'tr',
  'track',
  'tt',
  'u',
  'ul',
  'var',
  'video',
  'wbr'
]

const HTML_EVENT_ATTRIBUTES = [
  'onblur',
  'onchange',
  'oncontextmenu',
  'onfocus',
  'oninput',
  'oninvalid',
  'onreset',
  'onsearch',
  'onselect',
  'onsubmit',
  'onkeydown',
  'onkeypress',
  'onkeyup',
  'onclick',
  'ondblclick',
  'onmousedown',
  'onmousemove',
  'onmouseout',
  'onmouseover',
  'onmouseup',
  'onwheel',
  'ondrag',
  'ondragend',
  'ondragenter',
  'ondragleave',
  'ondragover',
  'ondragstart',
  'ondrop',
  'onscroll',
  'oncopy',
  'oncut',
  'onpaste'
]

class Expression {
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

  process(properties, children, component) {
    if (this.command === 'if') {
      const val = this.expression.eval(component)
      return Directive.isTrue(val)
    }
    if (this.command === 'bind') {
      const val = this.expression.eval(component)
      properties[this.target] = val
      return true
    }
    if (this.command === 'on') {
      let val = this.expression.eval(component)
      if (val && typeof val === 'function') {
        if (_.includes(this.params, 'native')) {
          properties[`on${this.target}`] = val
        }
      }
      return true
    }
    console.error('Illegal directive: %o', this)
    return true
  }
}

class Text {
  constructor(text) {
    this.text = text
  }

  render(component) {
    return new vdom.VText(this.text)
  }
}
class Node {
  constructor(tagName, properties, directives, children, componentClass) {
    this.tagName = tagName.toLowerCase()
    this.properties = properties || {}
    this.directives = directives || []
    this.children = children || []
    this.componentClass = componentClass
    if (componentClass) {
      this.componentId = `${componentClass.origin.name}_${Math.random().toString(36).substr(2, 9)}`
    }
  }

  render(component) {
    let properties = _.cloneDeep(this.properties)
    // only `onclick..` attributes is expression
    properties = _.mapValues(properties, attr => attr instanceof Expression ? attr.eval(component) : attr)
    const children = _.remove(this.children.map(child => child.render(component)), null)
    // start directiv processing
    for (let directive of this.directives) {
      if (!directive.process(properties, children, component)) return null
    }
    if (!this.componentClass) {
      return vdom.h(this.tagName, properties, children)
    }
    /* eslint new-cap: 0 */
    let childComponent = component.$children[this.componentId]
    if (!childComponent) {
      childComponent = new this['componentClass'](this.componentId, component, properties)
    }
    childComponent.$render()
    return childComponent.$vdom
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

function parseTag(tagName, attributes, componentClass) {
  const tag = tagName.toLowerCase()
  const properties = {}
  const directives = []
  if (_.includes(HTML_TAGS, tag)) { // HTML tags
    for (let name of Object.keys(attributes)) {
      if (name.match(/@[^@]+/)) { // directive prefix: @
        const directive = parseDirective(name, attributes[name])
        if (directive) directives.push(directive)
      } else if (_.includes(HTML_EVENT_ATTRIBUTES, name.toLowerCase())) {
        properties[name] = new Expression(attributes[name])
      } else {
        properties[name] = attributes[name]
      }
    }

    return new Node(tag, properties, directives, [])
  }
  const childComponentClass = componentClass.prototype.$lookupComponent(tag)
  if (childComponentClass) {
    for (let name of Object.keys(attributes)) {
      if (name.match(/@[^@]+/)) { // directive prefix: @
        const directive = parseDirective(name, attributes[name])
        if (directive) directives.push(directive)
      } else {
        // validate component props
        if (_.includes(Object.keys(childComponentClass.prototype.$props), name)) {
          properties[name] = attributes[name]
        } else {
          console.warn('Illegal commponent props %s in %s', name, childComponentClass.name)
        }
      }
    }
    return new Node(tag, properties, directives, [], childComponentClass)
  }
  throw Error('Cannot find component for custom tag: ' + tag)
}

export function parse(template, componentClass) {
  const roots = []
  const stack = []
  /* eslint no-unused-vars: 0 */
  let ast = null

  function onOpenTag(tagName, attributes) {
    console.debug(`<${tagName}>`)
    console.debug(attributes)
    const node = parseTag(tagName, attributes, componentClass)
    stack.push(node)
    console.debug(stack)
  }

  function onText(text) {
    stack[stack.length - 1].children.push(...parseText(text))
  }

  function onCloseTag(tagName) {
    console.debug(`</${tagName}>`)
    const node = stack.splice(-1)[0]
    // console.log(node)
    console.debug(stack)
    if (node.tagName !== tagName.toLowerCase()) {
      throw new Error('Tags are not closed correctly: ' + tagName)
    }
    if (stack.length === 0) {
      roots.push(node)
    } else {
      stack[stack.length - 1].children.push(node)
    }
    console.debug(stack)
  }

  function onEnd() {
    if (roots.length === 1) {
      ast = roots[0]
      return;
    }
    throw new Error('Template only supports single root.')
  }

  const parser = new htmlparser.Parser({
    onopentag: onOpenTag,
    ontext: onText,
    onclosetag: onCloseTag,
    onend: onEnd
  }, {decodeEntities: true});

  parser.write(template)
  parser.done()

  // attach parsed ast to component prototype
  Object.defineProperty(componentClass.prototype, '$template', {value: ast})
}
