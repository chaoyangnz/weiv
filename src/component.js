// @flow
import { VNode as VirtualNode, diff, createElement, patch } from 'virtual-dom'
import _ from 'lodash'

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

export class ComponentMeta {
  name: string
  target: string
  template: string
  props: {[string]: Prop}

  constructor(options: Options) {
    if (options.target) {
      this.target = options.target
    }
    if (options.template) {
      this.template = options.template
    }
    if (options.props) {
      this.props = _.cloneDeep(options.props)
    }
  }

  isRoot() {
    return !!this.target
  }
}

export class WeivComponent {
  $meta: ComponentMeta
  // only mounted component has a root tree
  $tree: VirtualNode
  $dom: Element
  // parent component
  $parent: WeivComponent
  $root: WeivComponent
  // generate after compile the template
  $render: () => VirtualNode

  constructor() {
    // init instance from meta
    // trigger $created lifecycle hook
  }

  // create component props properties as per $props declaration
  $initProps() {
    // TODO
  }

  $mount() {
    if (!this.$meta.isRoot()) return
    const tree = this.$render()
    this.$tree = tree
    const dom: any = createElement(tree)
    this.$dom = dom
    const mountNode = document.getElementById(this.$meta.target.substr(1))
    if (!mountNode) {
      throw new Error('Cannot find DOM element: ' + this.$meta.target)
    }
    mountNode.appendChild(dom)
  }
}

export function Component(options: Options) {
  return function (componentClass: any) {
    componentClass.prototype = new WeivComponent()
    componentClass.prototype.$meta = new ComponentMeta(options)
  }
}

export class Weiv {
  static components: Map<string, Component> = new Map()
  static component(tag: string, component: Component) {
    this.components.set(tag, component)
  }

  static patch(componentInstance: Component) {
    if (!componentInstance.$isRoot()) return
    const tree = componentInstance.$render()
    const patches = diff(componentInstance.$tree, tree)
    componentInstance.$dom = patch(componentInstance.$dom, patches)
    componentInstance.$tree = tree
  }

  static startup() {}
}
