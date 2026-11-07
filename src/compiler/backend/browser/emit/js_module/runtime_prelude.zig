const std = @import("std");

pub fn emitPrelude(out: *std.ArrayList(u8), allocator: std.mem.Allocator) !void {
    try out.appendSlice(allocator,
        \\function replaceBetween(start, end, content) {
        \\  const parent = start.parentNode;
        \\  if (!parent || parent !== end.parentNode) {
        \\    throw new Error("Conditional boundary is detached");
        \\  }
        \\  let current = start.nextSibling;
        \\  while (current && current !== end) {
        \\    const next = current.nextSibling;
        \\    parent.removeChild(current);
        \\    current = next;
        \\  }
        \\  parent.insertBefore(content, end);
        \\}
        \\
        \\function moveBoundaryBefore(start, end, reference) {
        \\  const parent = reference.parentNode;
        \\  if (!parent || parent !== start.parentNode || parent !== end.parentNode) {
        \\    throw new Error("Boundary move target is detached");
        \\  }
        \\  const nodes = [];
        \\  let current = start;
        \\  while (current) {
        \\    nodes.push(current);
        \\    if (current === end) break;
        \\    current = current.nextSibling;
        \\  }
        \\  for (const node of nodes) {
        \\    parent.insertBefore(node, reference);
        \\  }
        \\}
        \\
        \\function normalizeDirtyState(dirtyState) {
        \\  if (Array.isArray(dirtyState)) {
        \\    return { bindings: dirtyState, paths: [], preciseBindings: [] };
        \\  }
        \\  if (!dirtyState || typeof dirtyState !== "object") {
        \\    return { bindings: [], paths: [], preciseBindings: [] };
        \\  }
        \\  return {
        \\    bindings: Array.isArray(dirtyState.bindings) ? dirtyState.bindings : [],
        \\    paths: Array.isArray(dirtyState.paths) ? dirtyState.paths : [],
        \\    preciseBindings: Array.isArray(dirtyState.preciseBindings) ? dirtyState.preciseBindings : [],
        \\  };
        \\}
        \\
    );
}
