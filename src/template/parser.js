import _ from 'lodash'
import htmlparser from 'htmlparser2'
import debug from 'debug'
import { HTML_TAGS, BOOLEAN_ATTRIBUTES } from './html'
import { Node, Component, Text, Expression, Slot } from './ast'

const log = debug('weiv:parse')

export function parse(template, contextComponentClass) {
  if (_.isEmpty(template)) return new Text('')
  const roots = []
  const stack = []
  let ast = null

  function parseText(text) {
    const arr = []
    const pattern = /{{\s*[\w\._\$\[\]\(\)]+\s*}}/g
    const m = text.match(pattern) || []
    const expressions = m.map(x => x.match(/[\w\._\$\[\]\(\)]+/)[0])
    const texts = text.split(pattern)
    for (let i = 0; i < Math.max(expressions.length, texts.length); ++i) {
      if (i < texts.length && !texts[i].match(/^\s*$/)) arr.push(new Text(texts[i]))
      if (i < expressions.length) arr.push(new Expression(expressions[i]))
    }
    return arr
  }

  function parseTag(tagName, attributes, contextComponentClass) {
    // process boolean attributes
    BOOLEAN_ATTRIBUTES.forEach(([a, t, av]) => {
      if (tagName === t && _.keys(attributes).includes(a)) {
        if (!av || (av && attributes.type === av.type)) {
          if (attributes[a] !== 'false') { // htmlparser2 always get '' it has no value
            attributes[a] = true
          }
        }
      }
    })

    if (_.includes(HTML_TAGS, tagName)) { // HTML tags
      return new Node(contextComponentClass, tagName, attributes)
    }
    if (tagName === 'slot') {
      const slot = new Slot(contextComponentClass, tagName, attributes)
      contextComponentClass.prototype.$slots.add(slot.name)
      return slot
    }
    const childComponentClass = contextComponentClass.prototype.$lookupComponent(tagName) // custom tag for component
    if (childComponentClass) {
      return new Component(contextComponentClass, tagName, attributes, childComponentClass)
    }
    reportParseError('Cannot find component for custom tag: ' + tagName)
  }

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
    if (node.tagName !== tagName) {
      reportParseError('Tag is not closed correctly: ' + tagName)
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
    reportParseError('Template only supports single root.')
  }

  const onError = (err) => {
    reportParseError(err)
  }

  const parser = new htmlparser.Parser({
    onopentag: onOpenTag,
    ontext: onText,
    onclosetag: onCloseTag,
    onend: onEnd,
    onerror: onError
  }, {
    lowerCaseTags: true,
    lowerCaseAttributeNames: true,
    decodeEntities: true});

  function reportParseError(message) {
    console.groupEnd()
    const { startIndex, endIndex } = parser
    console.info('%s%c%s', template.substring(0, startIndex),
      'background: yellow; font-weight: bold;',
      template.substring(startIndex, endIndex),
      template.substring(endIndex)
    )

    throw new Error('[Parser] ' + message)
  }

  console.groupCollapsed('Parse template: %o', contextComponentClass.name)
  parser.write(template)
  parser.done()
  console.groupEnd()

  return ast
}
