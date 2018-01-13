
const Weiv = {
  $components: new Map(),

  component(tag: string, componentClass: any) {
    this.$components.set(tag, componentClass)
  }
}

export default Weiv;
