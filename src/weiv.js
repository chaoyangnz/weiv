
import vdom from 'virtual-dom'
import { autorun } from 'mobx'

const Weiv = {
  components: new Map(),

  component(tag: string, component: any) {
    this.components.set(tag, component)
  },

  mount(component: any) {
    if (!component.$isRoot()) return
    autorun(() => {
      const tree = component.$tree // old tree
      component.$render()
      if (tree) {
        const patches = vdom.diff(tree, component.$tree)
        console.log('%o', patches)
        component.$dom = vdom.patch(component.$dom, patches)
      } else {
        const dom: any = vdom.create(component.$tree)
        component.$dom = dom
        const mountNode = document.getElementById(component.$target.substr(1))
        if (!mountNode) {
          throw new Error('Cannot find DOM element: ' + component.$target)
        }
        mountNode.appendChild(dom)
      }
    })
  },

  startup() {}
}

export default Weiv;
