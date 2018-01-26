import _ from 'lodash'
import htmlparser from 'htmlparser2'
import debug from 'debug'
import { HTML_TAGS } from './html'
import { Node, Component, Text, Expression, Slot } from './ast'

const log = debug('weiv:parse')

function parseText(text) {
  const arr = []
  const pattern = /{{\s*[\w\.]+\s*}}/g
  const m = text.match(pattern) || []
  const expressions = m.map(x => x.match(/[\w\.]+/)[0])
  const texts = text.split(pattern)
  for (let i = 0; i < Math.max(expressions.length, texts.length); ++i) {
    if (i < texts.length && !texts[i].match(/^\s*$/)) arr.push(new Text(texts[i]))
    if (i < expressions.length) arr.push(new Expression(expressions[i]))
  }
  return arr
}

function parseTag(tagName, attributes, contextComponentClass) {
  const tag = tagName.toLowerCase()
  if (_.includes(HTML_TAGS, tag)) { // HTML tags
    return new Node(contextComponentClass, tag, attributes)
  }
  if (tag === 'slot') {
    const slot = new Slot(contextComponentClass, tag, attributes)
    contextComponentClass.prototype.$slots.add(slot.name)
    return slot
  }
  const childComponentClass = contextComponentClass.prototype.$lookupComponent(tag) // custom tag for component
  if (childComponentClass) {
    return new Component(contextComponentClass, tag, attributes, childComponentClass)
  }
  throw Error('Cannot find component for custom tag: ' + tag)
}

export function parse(template, contextComponentClass) {
  if (_.isEmpty(template)) return new Text('')
  const roots = []
  const stack = []
  let ast = null

  const onOpenTag = (tagName, attributes) => {
    console.group('<%s> attrs: %o', tagName, attributes)
    const node = parseTag(tagName, attributes, contextComponentClass)
    stack.push(node)
    // log(stack)
  }

  const onText = (text) => {
    const textsAndExpressions = parseText(text)
    log('Text: %j ==> %o', text, textsAndExpressions)
    stack[stack.length - 1].children.push(...textsAndExpressions)
  }

  const onCloseTag = (tagName) => {
    // log('</%s>', tagName)
    console.groupEnd()
    const node = stack.splice(-1)[0]
    // log(node)
    // log(stack)
    if (node.tagName !== tagName.toLowerCase()) {
      throw new Error('Tag is not closed correctly: ' + tagName)
    }
    if (stack.length === 0) {
      roots.push(node)
    } else {
      const parent = stack[stack.length - 1]
      parent.children.push(node)
      node.parent = parent
    }
    // log(stack)
  }

  const onEnd = () => {
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

  console.groupCollapsed('Parse template: %o', contextComponentClass.name)
  parser.write(template)
  parser.done()
  console.groupEnd()

  return ast
}
