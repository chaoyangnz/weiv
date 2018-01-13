import _ from 'lodash'
import htmlparser from 'htmlparser2'
import { HTML_TAGS } from './html'
import { Node, Component, Text, Expression, Directive } from './ast'

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
    return new Node(tag, attributes)
  }
  const childComponentClass = componentClass.prototype.$lookupComponent(tag)
  if (childComponentClass) {
    return new Component(tag, attributes, childComponentClass)
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

  return ast
}
