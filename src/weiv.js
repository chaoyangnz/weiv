
import vdom from 'virtual-dom'

const Weiv = {
  components: new Map(),

  component(tag: string, component: any) {
    this.components.set(tag, component)
  },

  patch(component: any) {
    if (!component.$isRoot()) return
    const tree = component.$render()
    const patches = vdom.diff(component.$tree, tree)
    component.$dom = vdom.patch(component.$dom, patches)
    component.$tree = tree
  },

  mount(component: any) {
    if (!component.$isRoot()) return
    const tree = component.$render()
    component.$tree = tree
    const dom: any = vdom.create(tree)
    component.$dom = dom
    const mountNode = document.getElementById(component.$target.substr(1))
    if (!mountNode) {
      throw new Error('Cannot find DOM element: ' + component.$target)
    }
    mountNode.appendChild(dom)
  },

  startup() {}
}

export default Weiv;
