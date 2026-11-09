// Immutable JavaScript fragments transcribed from the reference emitter. Functions avoid top-level string lowering gaps.
pub fn prelude(): string {
    return "function replaceBetween(start, end, content) {\n  const parent = start.parentNode;\n  if (!parent || parent !== end.parentNode) {\n    throw new Error(\"Conditional boundary is detached\");\n  }\n  let current = start.nextSibling;\n  while (current && current !== end) {\n    const next = current.nextSibling;\n    parent.removeChild(current);\n    current = next;\n  }\n  parent.insertBefore(content, end);\n}\n\nfunction moveBoundaryBefore(start, end, reference) {\n  const parent = reference.parentNode;\n  if (!parent || parent !== start.parentNode || parent !== end.parentNode) {\n    throw new Error(\"Boundary move target is detached\");\n  }\n  const nodes = [];\n  let current = start;\n  while (current) {\n    nodes.push(current);\n    if (current === end) break;\n    current = current.nextSibling;\n  }\n  for (const node of nodes) {\n    parent.insertBefore(node, reference);\n  }\n}\n\nfunction normalizeDirtyState(dirtyState) {\n  if (Array.isArray(dirtyState)) {\n    return { bindings: dirtyState, paths: [], preciseBindings: [] };\n  }\n  if (!dirtyState || typeof dirtyState !== \"object\") {\n    return { bindings: [], paths: [], preciseBindings: [] };\n  }\n  return {\n    bindings: Array.isArray(dirtyState.bindings) ? dirtyState.bindings : [],\n    paths: Array.isArray(dirtyState.paths) ? dirtyState.paths : [],\n    preciseBindings: Array.isArray(dirtyState.preciseBindings) ? dirtyState.preciseBindings : [],\n  };\n}\n";
}
pub fn create_header(): string {
    return "function createDom(instance) {\n  const fragment = document.createDocumentFragment();\n  const refs = instance.refs;\n";
}
pub fn create_footer(): string {
    return "  return fragment;\n}\n";
}
pub fn update_header(): string {
    return "function updateDom(instance) {\n  const refs = instance.refs;\n  const scope = instance.refresh();\n";
}
pub fn update_footer(): string {
    return "}\n";
}
pub fn dirty_header(): string {
    return "function updateDirtyRegions(instance, dirtyState, scope = instance.refresh()) {\n  const refs = instance.refs;\n  const normalizedDirtyState = normalizeDirtyState(dirtyState);\n  const dirtySet = new Set(normalizedDirtyState.bindings);\n  const preciseBindingSet = new Set(normalizedDirtyState.preciseBindings);\n  const dirtyPathSet = new Set(normalizedDirtyState.paths);\n  const dirtyRegionSet = new Set();\n  if (dirtyPathSet.size > 0 && trackedStateGraph && Array.isArray(trackedStateGraph.regions)) {\n    for (const region of trackedStateGraph.regions) {\n      if (!region || !Array.isArray(region.trackedPathIds)) continue;\n      for (const pathId of region.trackedPathIds) {\n        if (dirtyPathSet.has(pathId)) {\n          dirtyRegionSet.add(region.regionId);\n          break;\n        }\n      }\n    }\n  }\n";
}
pub fn dirty_footer(): string {
    return "}\n";
}
pub fn destroy_header(): string {
    return "function destroyDom(instance) {\n  const refs = instance.refs;\n";
}
pub fn destroy_footer(): string {
    return "}\n";
}
pub fn mount_exports(): string {
    return "\nexport function createInstance(props = {}, eventHandlers = {}, slots = {}) {\n  const base = setup(props, eventHandlers);\n  const instance = {\n    scope: base.scope,\n    refresh: base.refresh,\n    setProps: base.setProps,\n    setEventHandlers: base.setEventHandlers,\n    subscribeImportedObservables: base.subscribeImportedObservables,\n    slots,\n    setSlots: (nextSlots = {}) => { instance.slots = nextSlots; },\n    refs: [],\n    destroyed: false,\n    update: () => {},\n    updateDirty: () => {},\n    destroy: () => {},\n  };\n  return instance;\n}\n\nexport function mountIntoBoundary(start, end, props = {}, eventHandlers = {}, slots = {}) {\n  const instance = createInstance(props, eventHandlers, slots);\n  instance.setSlots = (nextSlots = {}) => { instance.slots = nextSlots; };\n  const fragment = createDom(instance);\n  replaceBetween(start, end, fragment);\n  instance.update = () => updateDom(instance);\n  instance.updateDirty = (dirtyBindings, scope) => updateDirtyRegions(instance, dirtyBindings, scope);\n  const __weiv_unsubscribeImportedObservables = typeof instance.subscribeImportedObservables === \"function\"\n    ? instance.subscribeImportedObservables(instance)\n    : null;\n  instance.destroy = () => { if (typeof __weiv_unsubscribeImportedObservables === \"function\") __weiv_unsubscribeImportedObservables(); instance.destroyed = true; destroyDom(instance); replaceBetween(start, end, document.createDocumentFragment()); };\n  instance.update();\n  return {\n    instance,\n    update: instance.update,\n    destroy: instance.destroy,\n    setProps: instance.setProps,\n    setEventHandlers: instance.setEventHandlers,\n    setSlots: instance.setSlots,\n    start,\n    end,\n  };\n}\n\nexport function mount(target, props = {}, eventHandlers = {}, slots = {}) {\n  const start = document.createComment(\"root:start\");\n  const end = document.createComment(\"root:end\");\n  target.replaceChildren(start, end);\n  return mountIntoBoundary(start, end, props, eventHandlers, slots);\n}\n";
}
pub fn setup_header(): string {
    return "function setup(__weiv_props, __weiv_event_handlers = {}) {\n  const __weiv_propsCell = __weiv_createCell(__weiv_props);\n  let props = __weiv_propsCell.value;\n  let __weiv_handlers = __weiv_event_handlers;  const emit = (name, payload) => {\n    if (typeof __weiv_handlers[name] === \"function\") {\n      return __weiv_handlers[name](payload);\n    }\n    return undefined;\n  };\n";
}
