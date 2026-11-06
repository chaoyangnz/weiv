const std = @import("std");
const browser_render_tree = @import("../../render_tree/index.zig");
const common = @import("common.zig");
const expression_codegen = @import("expression_codegen.zig");
const component_codegen = @import("component_codegen.zig");
const dom_create = @import("dom_create.zig");
const dom_update = @import("dom_update.zig");
const dom_destroy = @import("dom_destroy.zig");

pub fn emitStructuralHelpers(
    nodes: []const browser_render_tree.Node,
    scope_id: []const u8,
    bindings_json: []const u8,
    out: *std.ArrayList(u8),
    allocator: std.mem.Allocator,
) !void {
    for (nodes) |node| {
        switch (node) {
            .element => |element| try emitStructuralHelpers(element.children, scope_id, bindings_json, out, allocator),
            .conditional => |conditional| {
                try emitSingleConditionalHelper(conditional, scope_id, bindings_json, out, allocator);
                try emitStructuralHelpers(conditional.consequent, scope_id, bindings_json, out, allocator);
                try emitStructuralHelpers(conditional.alternate, scope_id, bindings_json, out, allocator);
            },
            .for_loop => |for_loop| {
                try emitSingleForLoopHelper(for_loop, scope_id, bindings_json, out, allocator);
                try emitStructuralHelpers(for_loop.body, scope_id, bindings_json, out, allocator);
            },
            .slot_outlet => |slot_outlet| {
                try emitSingleSlotFallbackHelper(slot_outlet, scope_id, out, allocator);
                try emitStructuralHelpers(slot_outlet.fallback_children, scope_id, bindings_json, out, allocator);
            },
            .component => |component_node| {
                for (component_node.slot_provisions) |slot_provision| {
                    try emitStructuralHelpers(slot_provision.children, scope_id, bindings_json, out, allocator);
                }
                if (component_node.slot_provisions.len > 0) {
                    try emitProjectedSlotHelpers(component_node, scope_id, out, allocator);
                }
            },
            .text, .interpolation => {},
        }
    }
}

fn emitSingleSlotFallbackHelper(
    slot_outlet: browser_render_tree.SlotOutletNode,
    scope_id: []const u8,
    out: *std.ArrayList(u8),
    allocator: std.mem.Allocator,
) !void {
    try out.print(
        allocator,
        "function createSlotFallbackFragment_{d}(instance, scope) {{\n  const refs = instance.refs;\n  const fragment = document.createDocumentFragment();\n",
        .{slot_outlet.handle_ref_id},
    );
    try out.print(allocator, "  fragment.__weiv_namespace = refs[{d}].parentNode?.localName === \"foreignObject\" ? undefined : refs[{d}].parentNode?.namespaceURI;\n", .{ slot_outlet.start_ref_id, slot_outlet.start_ref_id });
    for (slot_outlet.fallback_children) |child| {
        try dom_create.emitCreateNode(child, "fragment", scope_id, out, allocator, 1, "scope", "refs");
    }
    for (slot_outlet.fallback_children) |child| {
        try dom_update.emitUpdateNode(child, out, allocator, 1, "scope", "refs");
    }
    try out.appendSlice(allocator, "  return fragment;\n}\n\n");
}

fn emitProjectedSlotHelpers(
    component_node: browser_render_tree.ComponentNode,
    scope_id: []const u8,
    out: *std.ArrayList(u8),
    allocator: std.mem.Allocator,
) !void {
    for (component_node.slot_provisions, 0..) |slot_provision, idx| {
        try out.print(
            allocator,
            "function mountProjectedSlot_{d}_{d}(start, end, ownerInstance) {{\n  const instance = {{ refs: [], refresh: () => ownerInstance.refresh(), update: () => ownerInstance.update() }};\n  const refs = instance.refs;\n  const fragment = document.createDocumentFragment();\n",
            .{ component_node.handle_ref_id, idx },
        );
        try out.appendSlice(allocator, "  fragment.__weiv_namespace = start.parentNode?.localName === \"foreignObject\" ? undefined : start.parentNode?.namespaceURI;\n");
        for (slot_provision.children) |child| {
            try dom_create.emitCreateNode(child, "fragment", scope_id, out, allocator, 1, "instance.refresh()", "refs");
        }
        try out.appendSlice(allocator, "  replaceBetween(start, end, fragment);\n");
        try out.appendSlice(allocator, "  function update() {\n    const refs = instance.refs;\n    const scope = instance.refresh();\n");
        for (slot_provision.children) |child| {
            try dom_update.emitUpdateNode(child, out, allocator, 2, "scope", "refs");
        }
        try out.appendSlice(allocator, "  }\n  function destroy() {\n    const refs = instance.refs;\n");
        for (slot_provision.children) |child| {
            try dom_destroy.emitDestroyNode(child, out, allocator, 2, "refs");
        }
        try out.appendSlice(allocator, "  }\n  update();\n  return { update, destroy, start, end };\n}\n\n");
    }
}

fn emitSingleConditionalHelper(
    conditional: browser_render_tree.ConditionalNode,
    scope_id: []const u8,
    bindings_json: []const u8,
    out: *std.ArrayList(u8),
    allocator: std.mem.Allocator,
) !void {
    try out.print(
        allocator,
        "function createConditionalFragment_{d}(instance, scope, refs, isConsequent) {{\n  const fragment = document.createDocumentFragment();\n",
        .{conditional.start_ref_id},
    );
    try out.print(allocator, "  fragment.__weiv_namespace = refs[{d}].parentNode?.localName === \"foreignObject\" ? undefined : refs[{d}].parentNode?.namespaceURI;\n", .{ conditional.start_ref_id, conditional.start_ref_id });
    try out.appendSlice(allocator, "  if (isConsequent) {\n");
    for (conditional.consequent) |node| {
        try dom_create.emitCreateNode(node, "fragment", scope_id, out, allocator, 2, "scope", "refs");
    }
    try out.appendSlice(allocator, "  } else {\n");
    for (conditional.alternate) |node| {
        try dom_create.emitCreateNode(node, "fragment", scope_id, out, allocator, 2, "scope", "refs");
    }
    try out.appendSlice(allocator, "  }\n  return fragment;\n}\n\n");

    try out.print(
        allocator,
        "function destroyConditionalBranch_{d}(instance, refs, wasConsequent) {{\n  if (wasConsequent) {{\n",
        .{conditional.start_ref_id},
    );
    for (conditional.consequent) |node| {
        try dom_destroy.emitDestroyNode(node, out, allocator, 2, "refs");
    }
    try out.appendSlice(allocator, "  } else {\n");
    for (conditional.alternate) |node| {
        try dom_destroy.emitDestroyNode(node, out, allocator, 2, "refs");
    }
    try out.appendSlice(allocator, "  }\n}\n\n");

    try out.print(
        allocator,
        "function updateConditional_{d}(instance, scope, refs) {{\n  const next = Boolean(",
        .{conditional.start_ref_id},
    );
    try expression_codegen.emitResolvedExpression(conditional.condition, "scope", bindings_json, out, allocator);
    try out.print(
        allocator,
        ");\n  if (refs[{d}] !== next) {{\n    const previous = refs[{d}];\n    destroyConditionalBranch_{d}(instance, refs, previous === true);\n    refs[{d}] = next;\n    replaceBetween(refs[{d}], refs[{d}], createConditionalFragment_{d}(instance, scope, refs, next));\n  }}\n",
        .{
            conditional.state_ref_id,
            conditional.state_ref_id,
            conditional.start_ref_id,
            conditional.state_ref_id,
            conditional.start_ref_id,
            conditional.end_ref_id,
            conditional.start_ref_id,
        },
    );
    try out.appendSlice(allocator, "  if (next) {\n");
    for (conditional.consequent) |node| {
        try dom_update.emitUpdateNode(node, out, allocator, 2, "scope", "refs");
    }
    try out.appendSlice(allocator, "  } else {\n");
    for (conditional.alternate) |node| {
        try dom_update.emitUpdateNode(node, out, allocator, 2, "scope", "refs");
    }
    try out.appendSlice(allocator, "  }\n}\n\n");
}

fn emitSingleForLoopHelper(
    for_loop: browser_render_tree.ForLoopNode,
    scope_id: []const u8,
    bindings_json: []const u8,
    out: *std.ArrayList(u8),
    allocator: std.mem.Allocator,
) !void {
    if (for_loop.body.len == 1 and std.meta.activeTag(for_loop.body[0]) == .component) {
        const component_node = for_loop.body[0].component;
        try emitKeyedComponentLoopHelper(for_loop, component_node, bindings_json, out, allocator);
        return;
    }
    try emitKeyedGenericLoopHelper(for_loop, scope_id, bindings_json, out, allocator);
}

fn emitKeyedComponentLoopHelper(
    for_loop: browser_render_tree.ForLoopNode,
    component_node: browser_render_tree.ComponentNode,
    bindings_json: []const u8,
    out: *std.ArrayList(u8),
    allocator: std.mem.Allocator,
) !void {
    const has_props = component_codegen.componentHasProps(component_node);
    const has_handlers = component_codegen.componentHasEventHandlers(component_node);
    const has_slots = component_codegen.componentHasSlots(component_node);
    const needs_update = component_codegen.componentNeedsParentUpdate(component_node);
    try out.print(
        allocator,
        "function createForComponentEntry_{d}(instance, scope, item, reference) {{\n  const parent = reference.parentNode;\n  const start = document.createComment(\"for:item:start\");\n  const end = document.createComment(\"for:item:end\");\n  parent.insertBefore(start, reference);\n  parent.insertBefore(end, reference);\n  const loopScope = {{ ...scope, [",
        .{for_loop.start_ref_id},
    );
    try common.emitString(for_loop.item_name, out, allocator);
    try out.appendSlice(allocator, "]: item };\n");
    if (has_props) {
        try out.appendSlice(allocator, "  const props = ");
        try component_codegen.emitPropsObject(component_node.bind_effects, out, allocator, "loopScope", bindings_json);
        try out.appendSlice(allocator, ";\n");
    }
    if (has_handlers) {
        try out.appendSlice(allocator, "  const handlers = ");
        try component_codegen.emitChildHandlersObject(component_node.event_effects, out, allocator, "loopScope", bindings_json);
        try out.appendSlice(allocator, ";\n");
    }
    if (has_slots) {
        try out.appendSlice(allocator, "  const slotOwner = { refresh: () => loopScope, update: () => instance.update() };\n");
        try out.appendSlice(allocator, "  const slots = ");
        try common.emitProjectedSlotObject(component_node, "slotOwner", out, allocator);
        try out.appendSlice(allocator, ";\n");
    }
    try out.print(
        allocator,
        "  const handle = {s}.mountIntoBoundary(start, end, {s}, {s}, {s});\n  return {{ key: item?.id ?? item, start, end, handle }};\n}}\n\n",
        .{
            component_node.tag_name,
            if (has_props) "props" else "undefined",
            if (has_handlers) "handlers" else "undefined",
            if (has_slots) "slots" else "undefined",
        },
    );

    try out.print(
        allocator,
        "function updateForLoop_{d}(instance, scope, refs) {{\n  const iterable = (",
        .{for_loop.start_ref_id},
    );
    try expression_codegen.emitResolvedExpression(for_loop.iterable_expr, "scope", bindings_json, out, allocator);
    try out.print(
        allocator,
        ") ?? [];\n  const previous = refs[{d}] ?? [];\n  const previousByKey = new Map(previous.map((record) => [record.key, record]));\n  const nextRecords = [];\n  for (const item of iterable) {{\n    const key = item?.id ?? item;\n    let record = previousByKey.get(key);\n    const loopScope = {{ ...scope, [",
        .{for_loop.state_ref_id},
    );
    try common.emitString(for_loop.item_name, out, allocator);
    try out.appendSlice(allocator, "]: item };\n    if (record) {\n      previousByKey.delete(key);\n");
    if (has_props) {
        try out.appendSlice(allocator, "      record.handle.setProps(");
        try component_codegen.emitPropsObject(component_node.bind_effects, out, allocator, "loopScope", bindings_json);
        try out.appendSlice(allocator, ");\n");
    }
    if (has_handlers) {
        try out.appendSlice(allocator, "      record.handle.setEventHandlers(");
        try component_codegen.emitChildHandlersObject(component_node.event_effects, out, allocator, "loopScope", bindings_json);
        try out.appendSlice(allocator, ");\n");
    }
    if (has_slots) {
        try out.appendSlice(allocator, "      const slotOwner = { refresh: () => loopScope, update: () => instance.update() };\n");
        try out.appendSlice(allocator, "      record.handle.setSlots(");
        try common.emitProjectedSlotObject(component_node, "slotOwner", out, allocator);
        try out.appendSlice(allocator, ");\n");
    }
    if (needs_update) {
        try out.appendSlice(allocator, "      record.handle.update();\n");
    }
    try out.print(
        allocator,
        "      moveBoundaryBefore(record.start, record.end, refs[{d}]);\n    }} else {{\n      record = createForComponentEntry_{d}(instance, scope, item, refs[{d}]);\n    }}\n    nextRecords.push(record);\n  }}\n  for (const record of previousByKey.values()) {{\n    if (record.handle && typeof record.handle.destroy === \"function\") {{\n      record.handle.destroy();\n    }}\n    replaceBetween(record.start, record.end, document.createDocumentFragment());\n    record.start.parentNode.removeChild(record.start);\n    record.end.parentNode.removeChild(record.end);\n  }}\n  refs[{d}] = nextRecords;\n}}\n\n",
        .{ for_loop.end_ref_id, for_loop.start_ref_id, for_loop.end_ref_id, for_loop.state_ref_id },
    );
}

fn emitKeyedGenericLoopHelper(
    for_loop: browser_render_tree.ForLoopNode,
    scope_id: []const u8,
    bindings_json: []const u8,
    out: *std.ArrayList(u8),
    allocator: std.mem.Allocator,
) !void {
    try out.print(
        allocator,
        "function createForEntry_{d}(instance, scope, item, reference) {{\n  const parent = reference.parentNode;\n  const start = document.createComment(\"for:item:start\");\n  const end = document.createComment(\"for:item:end\");\n  parent.insertBefore(start, reference);\n  parent.insertBefore(end, reference);\n  const entryRefs = [];\n  let currentItem = item;\n  let loopScope = {{ ...scope, [",
        .{for_loop.start_ref_id},
    );
    try common.emitString(for_loop.item_name, out, allocator);
    try out.appendSlice(allocator, "]: currentItem };\n  function update(nextScope, nextItem) {\n    if (arguments.length > 1) currentItem = nextItem;\n    const refs = entryRefs;\n    loopScope = { ...nextScope, [");
    try common.emitString(for_loop.item_name, out, allocator);
    try out.appendSlice(allocator, "]: currentItem };\n");
    for (for_loop.body) |node| {
        try dom_update.emitUpdateNode(node, out, allocator, 2, "loopScope", "entryRefs");
    }
    try out.appendSlice(allocator, "  }\n  const fragment = document.createDocumentFragment();\n  fragment.__weiv_namespace = parent.localName === \"foreignObject\" ? undefined : parent.namespaceURI;\n");
    for (for_loop.body) |node| {
        try dom_create.emitCreateNode(node, "fragment", scope_id, out, allocator, 1, "loopScope", "entryRefs");
    }
    try out.appendSlice(allocator, "  function destroy() {\n    const refs = entryRefs;\n");
    for (for_loop.body) |node| {
        try dom_destroy.emitDestroyNode(node, out, allocator, 2, "entryRefs");
    }
    try out.appendSlice(allocator, "  }\n  replaceBetween(start, end, fragment);\n  update(scope, item);\n  return { key: item?.id ?? item, start, end, refs: entryRefs, update, destroy };\n}\n\n");

    try out.print(
        allocator,
        "function updateForLoop_{d}(instance, scope, refs) {{\n  const iterable = (",
        .{for_loop.start_ref_id},
    );
    try expression_codegen.emitResolvedExpression(for_loop.iterable_expr, "scope", bindings_json, out, allocator);
    try out.print(
        allocator,
        ") ?? [];\n  const previous = refs[{d}] ?? [];\n  const previousByKey = new Map(previous.map((record) => [record.key, record]));\n  const nextRecords = [];\n  for (const item of iterable) {{\n    const key = item?.id ?? item;\n    let record = previousByKey.get(key);\n    if (record) {{\n      previousByKey.delete(key);\n      record.update(scope, item);\n      moveBoundaryBefore(record.start, record.end, refs[{d}]);\n    }} else {{\n      record = createForEntry_{d}(instance, scope, item, refs[{d}]);\n    }}\n    nextRecords.push(record);\n  }}\n  for (const record of previousByKey.values()) {{\n    if (typeof record.destroy === \"function\") {{\n      record.destroy();\n    }}\n    replaceBetween(record.start, record.end, document.createDocumentFragment());\n    record.start.parentNode.removeChild(record.start);\n    record.end.parentNode.removeChild(record.end);\n  }}\n  refs[{d}] = nextRecords;\n}}\n\n",
        .{ for_loop.state_ref_id, for_loop.end_ref_id, for_loop.start_ref_id, for_loop.end_ref_id, for_loop.state_ref_id },
    );
}
