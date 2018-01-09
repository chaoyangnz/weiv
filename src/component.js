// @flow
import { VNode, VText, h } from 'virtual-dom'
import _ from 'lodash'
import Hogan from 'hogan.js'
import html2Vdom from 'html-to-vdom'

const convertHtml = html2Vdom({VNode, VText})

export type Prop = {
  type: Function,
  default: any,
  required: boolean
}

export type Options = {
  name: string,
  target?: string,
  template?: string,
  props?: {[string]: Prop}
}

export type Meta = {
  $name: ?string,
  $target: ?string,
  $template: ?any,
  $props: {[string]: Prop},
  $render: () => VNode,
  $isRoot: () => boolean,
}

function createMeta(options: Options) {
  const meta: any = {}
  if (options.target) {
    meta.$target = options.target
  }
  if (options.template) {
    // this.$template = options.template
    meta.$template = Hogan.compile(options.template.trim())
  }
  if (options.props) {
    meta.$props = _.cloneDeep(options.props)
  }
  meta.$render = function () {
    if (this.$template) {
      const html = this.$template.render(this) // render Mustache template to HTML
      console.log('Rendered: %o', html)
      const tree = convertHtml(html) // convert HTML to VDOM
      if (Array.isArray(tree)) {
        throw new Error('Template only supports single root.')
      }
      this.$tree = tree
    } else {
      this.tree = h('div', {}, [])
    }
  }

  meta.$isRoot = function () {
    return !!this.$target
  }

  return meta
}

export class WeivComponent {
  // only mounted component has a root tree
  $tree: ?VNode = null
  $dom: ?HTMLElement = null
  // parent component
  $parent: ?WeivComponent = null
  $root: ?WeivComponent = null

  constructor() {
    // init instance from meta
    // trigger $created lifecycle hook
  }

  // create component props properties as per $props declaration
  initProps() {
    // TODO
  }
}

export function Component(options: Options) {
  return function decorator(ComponentClass: any) {
    Object.assign(ComponentClass.prototype, createMeta(options)) // share meta to all component instances
    const constructor = () => {
      const component = new ComponentClass()
      Object.assign(component, new WeivComponent()) // inject internal properties
      return component
    }
    constructor.prototype.constructor = ComponentClass
    return constructor
  }
}
