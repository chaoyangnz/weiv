
import VDOM from 'virtual-dom'
import { autorun } from 'mobx'

const Weiv = {
  components: new Map(),

  component(tag: string, component: any) {
    this.components.set(tag, component)
  },

  mount(component: any) {
    if (!component.$isRoot()) return
    autorun(() => {
      const vdom = component.$vdom // old vdom tree
      component.$render()
      if (vdom) {
        const patches = VDOM.diff(vdom, component.$vdom)
        console.log('%o', patches)
        component.$dom = VDOM.patch(component.$dom, patches)
      } else {
        const dom: any = VDOM.create(component.$vdom)
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
