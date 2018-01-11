
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
      console.info('Before: %o', vdom)
      component.$render()
      console.info('After: %o', component.$vdom)
      console.assert(vdom !== component.$vdom)
      if (vdom) {
        const patches = VDOM.diff(vdom, component.$vdom)
        console.info('Diff: %o', patches)
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
      console.info('After patch to DOM: %o', component.$dom)
    })
  },

  startup() {}
}

export default Weiv;
