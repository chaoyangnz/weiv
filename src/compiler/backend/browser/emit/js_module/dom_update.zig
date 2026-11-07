const std = @import("std");
const browser_render_tree = @import("../../render_tree/index.zig");
const lir = @import("../../../../lower/lir.zig");
const region_graph = @import("../../region_graph.zig");
const js_output = @import("output.zig");
const expressions = @import("expressions.zig");
const components = @import("components.zig");
const slots = @import("slots.zig");

pub fn emitUpdateFunction(
    render_tree: browser_render_tree.Document,
    out: *std.ArrayList(u8),
    allocator: std.mem.Allocator,
) !void {
    try out.appendSlice(allocator,
        \\function updateDom(instance) {
        \\  const refs = instance.refs;
        \\  const scope = instance.refresh();
        \\
    );
    for (render_tree.nodes) |node| {
        try emitUpdateNode(node, out, allocator, 1, "scope", "refs");
    }
    try out.appendSlice(allocator,
        \\}
        \\
    );
}

pub fn emitSelectiveUpdateFunction(
    graph: *const region_graph.Graph,
    render_tree: browser_render_tree.Document,
    out: *std.ArrayList(u8),
    allocator: std.mem.Allocator,
) !void {
    try out.appendSlice(allocator,
        \\function updateDirtyRegions(instance, dirtyState, scope = instance.refresh()) {
        \\  const refs = instance.refs;
        \\  const normalizedDirtyState = normalizeDirtyState(dirtyState);
        \\  const dirtySet = new Set(normalizedDirtyState.bindings);
        \\  const preciseBindingSet = new Set(normalizedDirtyState.preciseBindings);
        \\  const dirtyPathSet = new Set(normalizedDirtyState.paths);
        \\  const dirtyRegionSet = new Set();
        \\  if (dirtyPathSet.size > 0 && trackedStateGraph && Array.isArray(trackedStateGraph.regions)) {
        \\    for (const region of trackedStateGraph.regions) {
        \\      if (!region || !Array.isArray(region.trackedPathIds)) continue;
        \\      for (const pathId of region.trackedPathIds) {
        \\        if (dirtyPathSet.has(pathId)) {
        \\          dirtyRegionSet.add(region.regionId);
        \\          break;
        \\        }
        \\      }
        \\    }
        \\  }
        \\
    );
    var next_region_id: usize = 1;
    for (render_tree.nodes) |node| {
        try emitSelectiveUpdateNode(graph, node, out, allocator, 1, "scope", "refs", &next_region_id);
    }
    if (next_region_id != graph.regions.items.len + 1) return error.RegionGraphMismatch;
    try out.appendSlice(allocator,
        \\}
        \\
    );
}

pub fn emitRegionUpdateFunctions(
    render_tree: browser_render_tree.Document,
    bindings_json: []const u8,
    out: *std.ArrayList(u8),
    allocator: std.mem.Allocator,
) !void {
    for (render_tree.nodes) |node| {
        try emitRegionUpdateFunctionsForNode(node, bindings_json, out, allocator);
    }
}

fn emitRegionUpdateFunctionsForNode(
    node: browser_render_tree.Node,
    bindings_json: []const u8,
    out: *std.ArrayList(u8),
    allocator: std.mem.Allocator,
) !void {
    switch (node) {
        .text => {},
        .interpolation => |interp| {
            try emitTextRegionUpdateFunction(interp, bindings_json, out, allocator);
        },
        .element => |element| {
            for (element.bind_effects) |effect| {
                switch (effect) {
                    .bind => |bind_dir| try emitAttributeRegionUpdateFunction(
                        element.ref_id,
                        bind_dir.target_name,
                        bind_dir.expression,
                        staticAttributeValue(element.attributes, bind_dir.target_name),
                        bindings_json,
                        out,
                        allocator,
                    ),
                    .event => unreachable,
                }
            }
            for (element.children) |child| {
                try emitRegionUpdateFunctionsForNode(child, bindings_json, out, allocator);
            }
        },
        .conditional => |conditional| {
            try emitConditionalRegionUpdateFunction(conditional, bindings_json, out, allocator);
            for (conditional.consequent) |child| {
                try emitRegionUpdateFunctionsForNode(child, bindings_json, out, allocator);
            }
            for (conditional.alternate) |child| {
                try emitRegionUpdateFunctionsForNode(child, bindings_json, out, allocator);
            }
        },
        .for_loop => |for_loop| {
            try emitLoopRegionUpdateFunction(for_loop, bindings_json, out, allocator);
            for (for_loop.body) |child| {
                try emitRegionUpdateFunctionsForNode(child, bindings_json, out, allocator);
            }
        },
        .component => |component_node| {
            try emitChildRegionUpdateFunction(component_node, bindings_json, out, allocator);
            for (component_node.slot_provisions) |slot| {
                for (slot.children) |child| {
                    try emitRegionUpdateFunctionsForNode(child, bindings_json, out, allocator);
                }
            }
        },
        .slot_outlet => |slot_outlet| {
            try emitSlotRegionUpdateFunction(slot_outlet, bindings_json, out, allocator);
            for (slot_outlet.fallback_children) |child| {
                try emitRegionUpdateFunctionsForNode(child, bindings_json, out, allocator);
            }
        },
    }
}

fn emitTextRegionUpdateFunction(
    interp: browser_render_tree.InterpolationNode,
    bindings_json: []const u8,
    out: *std.ArrayList(u8),
    allocator: std.mem.Allocator,
) !void {
    try out.print(allocator, "function updateRegion_text_{d}(instance, scope, refs) {{\n", .{interp.ref_id});
    try emitInterpolationUpdate(interp, bindings_json, out, allocator, 1, "scope", "refs");
    try out.appendSlice(allocator, "}\n");
}

fn emitAttributeRegionUpdateFunction(
    ref_id: usize,
    target_name: []const u8,
    expression: []const u8,
    static_value: ?[]const u8,
    bindings_json: []const u8,
    out: *std.ArrayList(u8),
    allocator: std.mem.Allocator,
) !void {
    const suffix = try sanitizedIdentifierFragment(target_name, allocator);
    defer allocator.free(suffix);

    try out.print(allocator, "function updateRegion_attribute_{d}_{s}(instance, scope, refs) {{\n", .{ ref_id, suffix });
    try emitBoundAttributeUpdate(target_name, expression, static_value, "refs", ref_id, "scope", bindings_json, 1, out, allocator);
    try out.appendSlice(allocator, "}\n");
}

fn staticAttributeValue(attributes: []const lir.Attribute, name: []const u8) ?[]const u8 {
    for (attributes) |attribute| {
        if (std.mem.eql(u8, attribute.name, name)) return attribute.value orelse "";
    }
    return null;
}

fn emitConditionalRegionUpdateFunction(
    conditional: browser_render_tree.ConditionalNode,
    bindings_json: []const u8,
    out: *std.ArrayList(u8),
    allocator: std.mem.Allocator,
) !void {
    _ = bindings_json; // conditional regions delegate to updateConditional_ which handles its own expressions
    try out.print(allocator, "function updateRegion_conditional_{d}(instance, scope, refs) {{\n", .{conditional.start_ref_id});
    try js_output.writeIndent(1, out, allocator);
    try out.print(allocator, "updateConditional_{d}(instance, scope, refs);\n", .{conditional.start_ref_id});
    try out.appendSlice(allocator, "}\n");
}

fn emitLoopRegionUpdateFunction(
    for_loop: browser_render_tree.ForLoopNode,
    bindings_json: []const u8,
    out: *std.ArrayList(u8),
    allocator: std.mem.Allocator,
) !void {
    _ = bindings_json; // loop regions delegate to updateForLoop_ which handles its own expressions
    try out.print(allocator, "function updateRegion_loop_{d}(instance, scope, refs) {{\n", .{for_loop.start_ref_id});
    try js_output.writeIndent(1, out, allocator);
    try out.print(allocator, "updateForLoop_{d}(instance, scope, refs);\n", .{for_loop.start_ref_id});
    try out.appendSlice(allocator, "}\n");
}

fn emitChildRegionUpdateFunction(
    component_node: browser_render_tree.ComponentNode,
    bindings_json: []const u8,
    out: *std.ArrayList(u8),
    allocator: std.mem.Allocator,
) !void {
    try out.print(allocator, "function updateRegion_child_{d}(instance, scope, refs) {{\n", .{component_node.handle_ref_id});
    try out.print(allocator, "  if (!refs[{d}]) return;\n", .{component_node.handle_ref_id});
    try emitChildComponentUpdateBody(component_node, bindings_json, out, allocator, 1, "scope", "refs");
    try out.appendSlice(allocator, "}\n");
}

fn emitSlotRegionUpdateFunction(
    slot_outlet: browser_render_tree.SlotOutletNode,
    bindings_json: []const u8,
    out: *std.ArrayList(u8),
    allocator: std.mem.Allocator,
) !void {
    _ = bindings_json; // slot regions don't directly resolve expressions
    try out.print(allocator, "function updateRegion_slot_{d}(instance, scope, refs) {{\n", .{slot_outlet.handle_ref_id});
    try emitSlotOutletUpdateBody(slot_outlet, out, allocator, 1, "scope", "refs");
    try out.appendSlice(allocator, "}\n");
}

fn emitSelectiveUpdateNode(
    graph: *const region_graph.Graph,
    node: browser_render_tree.Node,
    out: *std.ArrayList(u8),
    allocator: std.mem.Allocator,
    indent: usize,
    scope_expr: []const u8,
    refs_expr: []const u8,
    next_region_id: *usize,
) !void {
    switch (node) {
        .text => {},
        .interpolation => |interp| {
            const region = try consumeRegion(graph, next_region_id, "text", interp.ref_id);
            const region_id = region.id;
            try emitSelectiveStep(indent, region.dependency_names.items, region.precise_import_name, region_id, out, allocator);
            try out.print(allocator, "updateRegion_text_{d}(instance, {s}, {s});\n", .{ interp.ref_id, scope_expr, refs_expr });
            if (region.dependency_names.items.len > 0 or region_id > 0) {
                try js_output.writeIndent(indent, out, allocator);
                try out.appendSlice(allocator, "}\n");
            }
        },
        .slot_outlet => |slot_outlet| {
            const region = try consumeRegion(graph, next_region_id, "slot", slot_outlet.handle_ref_id);
            const region_id = region.id;
            try emitSelectiveStep(indent, region.dependency_names.items, region.precise_import_name, region_id, out, allocator);
            try out.print(allocator, "updateRegion_slot_{d}(instance, {s}, {s});\n", .{ slot_outlet.handle_ref_id, scope_expr, refs_expr });
            if (region.dependency_names.items.len > 0 or region_id > 0) {
                try js_output.writeIndent(indent, out, allocator);
                try out.appendSlice(allocator, "}\n");
            }
        },
        .element => |element| {
            for (element.bind_effects) |effect| {
                switch (effect) {
                    .bind => |bind_dir| {
                        const region = try consumeRegion(graph, next_region_id, "attribute", element.ref_id);
                        const suffix = try sanitizedIdentifierFragment(bind_dir.target_name, allocator);
                        defer allocator.free(suffix);
                        const region_id = region.id;
                        try emitSelectiveStep(indent, region.dependency_names.items, region.precise_import_name, region_id, out, allocator);
                        try out.print(allocator, "updateRegion_attribute_{d}_{s}(instance, {s}, {s});\n", .{
                            element.ref_id,
                            suffix,
                            scope_expr,
                            refs_expr,
                        });
                        if (region.dependency_names.items.len > 0 or region_id > 0) {
                            try js_output.writeIndent(indent, out, allocator);
                            try out.appendSlice(allocator, "}\n");
                        }
                    },
                    .event => unreachable,
                }
            }
            for (element.children) |child| {
                try emitSelectiveUpdateNode(graph, child, out, allocator, indent, scope_expr, refs_expr, next_region_id);
            }
        },
        .conditional => |conditional| {
            const region = try consumeRegion(graph, next_region_id, "conditional", conditional.state_ref_id);
            const region_id = region.id;
            try emitSelectiveStep(indent, region.dependency_names.items, region.precise_import_name, region_id, out, allocator);
            try out.print(allocator, "updateRegion_conditional_{d}(instance, {s}, {s});\n", .{ conditional.start_ref_id, scope_expr, refs_expr });
            if (region.dependency_names.items.len > 0 or region_id > 0) {
                try js_output.writeIndent(indent, out, allocator);
                try out.appendSlice(allocator, "}\n");
            }
        },
        .component => |component_node| {
            const region = try consumeRegion(graph, next_region_id, "child", component_node.handle_ref_id);
            const region_id = region.id;
            try emitSelectiveStep(indent, region.dependency_names.items, region.precise_import_name, region_id, out, allocator);
            try out.print(allocator, "updateRegion_child_{d}(instance, {s}, {s});\n", .{ component_node.handle_ref_id, scope_expr, refs_expr });
            if (region.dependency_names.items.len > 0 or region_id > 0) {
                try js_output.writeIndent(indent, out, allocator);
                try out.appendSlice(allocator, "}\n");
            }
        },
        .for_loop => |for_loop| {
            const region = try consumeRegion(graph, next_region_id, "loop", for_loop.state_ref_id);
            const region_id = region.id;
            try emitSelectiveStep(indent, region.dependency_names.items, region.precise_import_name, region_id, out, allocator);
            try out.print(allocator, "updateRegion_loop_{d}(instance, {s}, {s});\n", .{ for_loop.start_ref_id, scope_expr, refs_expr });
            if (region.dependency_names.items.len > 0 or region_id > 0) {
                try js_output.writeIndent(indent, out, allocator);
                try out.appendSlice(allocator, "}\n");
            }
        },
    }
}

fn consumeRegion(graph: *const region_graph.Graph, next_region_id: *usize, kind: []const u8, ref_id: usize) !*const region_graph.Region {
    if (next_region_id.* == 0 or next_region_id.* > graph.regions.items.len) return error.RegionGraphMismatch;
    const region = graph.region(next_region_id.*);
    if (!std.mem.eql(u8, region.kind, kind) or region.ref_id != ref_id) return error.RegionGraphMismatch;
    next_region_id.* += 1;
    return region;
}

fn emitSelectiveStep(indent: usize, deps: []const []const u8, precise_import_name: ?[]const u8, region_id: usize, out: *std.ArrayList(u8), allocator: std.mem.Allocator) !void {
    if (deps.len == 0 and region_id == 0) return;
    try js_output.writeIndent(indent, out, allocator);
    try out.appendSlice(allocator, "if (");
    var wrote_clause = false;
    for (deps, 0..) |dep, idx| {
        _ = idx;
        if (wrote_clause) try out.appendSlice(allocator, " || ");
        try out.appendSlice(allocator, "dirtySet.has(");
        try js_output.emitString(dep, out, allocator);
        try out.appendSlice(allocator, ")");
        if (precise_import_name) |name| {
            if (std.mem.eql(u8, name, dep)) {
                try out.appendSlice(allocator, " && !preciseBindingSet.has(");
                try js_output.emitString(dep, out, allocator);
                try out.appendSlice(allocator, ")");
            }
        }
        wrote_clause = true;
    }
    if (region_id != 0) {
        if (wrote_clause) try out.appendSlice(allocator, " || ");
        try out.print(allocator, "dirtyRegionSet.has({d})", .{region_id});
    }
    try out.appendSlice(allocator, ") {\n");
    try js_output.writeIndent(indent + 1, out, allocator);
}

pub fn emitUpdateNode(
    node: browser_render_tree.Node,
    out: *std.ArrayList(u8),
    allocator: std.mem.Allocator,
    indent: usize,
    scope_expr: []const u8,
    refs_expr: []const u8,
) !void {
    switch (node) {
        .text => {},
        .interpolation => |interp| {
            try js_output.writeIndent(indent, out, allocator);
            try out.print(allocator, "updateRegion_text_{d}(instance, {s}, {s});\n", .{ interp.ref_id, scope_expr, refs_expr });
        },
        .slot_outlet => |slot_outlet| {
            try js_output.writeIndent(indent, out, allocator);
            try out.print(allocator, "updateRegion_slot_{d}(instance, {s}, {s});\n", .{ slot_outlet.handle_ref_id, scope_expr, refs_expr });
        },
        .element => |element| {
            for (element.bind_effects) |effect| {
                switch (effect) {
                    .bind => |bind_dir| {
                        const suffix = try sanitizedIdentifierFragment(bind_dir.target_name, allocator);
                        defer allocator.free(suffix);
                        try js_output.writeIndent(indent, out, allocator);
                        try out.print(allocator, "updateRegion_attribute_{d}_{s}(instance, {s}, {s});\n", .{
                            element.ref_id,
                            suffix,
                            scope_expr,
                            refs_expr,
                        });
                    },
                    .event => unreachable,
                }
            }
            for (element.children) |child| {
                try emitUpdateNode(child, out, allocator, indent, scope_expr, refs_expr);
            }
        },
        .conditional => |conditional| {
            try js_output.writeIndent(indent, out, allocator);
            try out.print(allocator, "updateRegion_conditional_{d}(instance, {s}, {s});\n", .{ conditional.start_ref_id, scope_expr, refs_expr });
        },
        .component => |component_node| {
            try js_output.writeIndent(indent, out, allocator);
            try out.print(allocator, "updateRegion_child_{d}(instance, {s}, {s});\n", .{ component_node.handle_ref_id, scope_expr, refs_expr });
        },
        .for_loop => |for_loop| {
            try js_output.writeIndent(indent, out, allocator);
            try out.print(allocator, "updateRegion_loop_{d}(instance, {s}, {s});\n", .{ for_loop.start_ref_id, scope_expr, refs_expr });
        },
    }
}

fn emitChildComponentUpdateBody(
    component_node: browser_render_tree.ComponentNode,
    bindings_json: []const u8,
    out: *std.ArrayList(u8),
    allocator: std.mem.Allocator,
    indent: usize,
    scope_expr: []const u8,
    refs_expr: []const u8,
) !void {
    if (components.componentHasProps(component_node)) {
        try js_output.writeIndent(indent, out, allocator);
        try out.print(allocator, "{s}[{d}].setProps(", .{ refs_expr, component_node.handle_ref_id });
        try components.emitPropsObject(component_node.bind_effects, out, allocator, scope_expr, bindings_json);
        try out.appendSlice(allocator, ");\n");
    }
    if (components.componentHasEventHandlers(component_node)) {
        try js_output.writeIndent(indent, out, allocator);
        try out.print(allocator, "{s}[{d}].setEventHandlers(", .{ refs_expr, component_node.handle_ref_id });
        try components.emitChildHandlersObject(component_node.event_effects, out, allocator, scope_expr, bindings_json);
        try out.appendSlice(allocator, ");\n");
    }
    if (components.componentHasSlots(component_node)) {
        try js_output.writeIndent(indent, out, allocator);
        try out.print(allocator, "{s}[{d}].setSlots(", .{
            refs_expr,
            component_node.handle_ref_id,
        });
        try slots.emitProjectedSlotObject(component_node, "instance", out, allocator);
        try out.appendSlice(allocator, ");\n");
    }
    if (components.componentNeedsParentUpdate(component_node)) {
        try js_output.writeIndent(indent, out, allocator);
        try out.print(allocator, "{s}[{d}].update();\n", .{ refs_expr, component_node.handle_ref_id });
    }
}

fn emitSlotOutletUpdateBody(
    slot_outlet: browser_render_tree.SlotOutletNode,
    out: *std.ArrayList(u8),
    allocator: std.mem.Allocator,
    indent: usize,
    scope_expr: []const u8,
    refs_expr: []const u8,
) !void {
    const next_slot_var_name = try std.fmt.allocPrint(allocator, "__next_slot_{d}", .{slot_outlet.handle_ref_id});
    defer allocator.free(next_slot_var_name);
    const current_slot_var_name = try std.fmt.allocPrint(allocator, "__current_slot_{d}", .{slot_outlet.handle_ref_id});
    defer allocator.free(current_slot_var_name);
    try slots.emitSlotLookupLine(slot_outlet, next_slot_var_name, indent, out, allocator);
    try js_output.writeIndent(indent, out, allocator);
    try out.print(allocator, "const {s} = {s}[{d}];\n", .{
        current_slot_var_name,
        refs_expr,
        slot_outlet.handle_ref_id,
    });
    try js_output.writeIndent(indent, out, allocator);
    try out.print(allocator, "if ({s}) {{\n", .{next_slot_var_name});
    try js_output.writeIndent(indent + 1, out, allocator);
    try out.print(allocator, "if ({s} && {s} !== false) {{\n", .{
        current_slot_var_name,
        current_slot_var_name,
    });
    try js_output.writeIndent(indent + 2, out, allocator);
    try out.print(allocator, "{s}.update();\n", .{current_slot_var_name});
    try js_output.writeIndent(indent + 1, out, allocator);
    try out.appendSlice(allocator, "} else {\n");
    try js_output.writeIndent(indent + 2, out, allocator);
    try out.print(allocator, "{s}[{d}] = {s}.mountIntoBoundary({s}[{d}], {s}[{d}]);\n", .{
        refs_expr,
        slot_outlet.handle_ref_id,
        next_slot_var_name,
        refs_expr,
        slot_outlet.start_ref_id,
        refs_expr,
        slot_outlet.end_ref_id,
    });
    try js_output.writeIndent(indent + 1, out, allocator);
    try out.appendSlice(allocator, "}\n");
    try js_output.writeIndent(indent, out, allocator);
    try out.appendSlice(allocator, "} else {\n");
    try js_output.writeIndent(indent + 1, out, allocator);
    try out.print(allocator, "if ({s} !== false) {{\n", .{current_slot_var_name});
    try js_output.writeIndent(indent + 2, out, allocator);
    try out.print(allocator, "if ({s} && typeof {s}.destroy === \"function\") {{ {s}.destroy(); }}\n", .{
        current_slot_var_name,
        current_slot_var_name,
        current_slot_var_name,
    });
    try js_output.writeIndent(indent + 2, out, allocator);
    try out.print(allocator, "{s}[{d}] = false;\n", .{ refs_expr, slot_outlet.handle_ref_id });
    const start_ref_expr = try std.fmt.allocPrint(allocator, "{s}[{d}]", .{ refs_expr, slot_outlet.start_ref_id });
    defer allocator.free(start_ref_expr);
    const end_ref_expr = try std.fmt.allocPrint(allocator, "{s}[{d}]", .{ refs_expr, slot_outlet.end_ref_id });
    defer allocator.free(end_ref_expr);
    try slots.emitSlotFallbackReplaceLine(slot_outlet, start_ref_expr, end_ref_expr, scope_expr, indent + 2, out, allocator);
    try js_output.writeIndent(indent + 1, out, allocator);
    try out.appendSlice(allocator, "}\n");
    for (slot_outlet.fallback_children) |child| {
        try emitUpdateNode(child, out, allocator, indent + 1, scope_expr, refs_expr);
    }
    try js_output.writeIndent(indent, out, allocator);
    try out.appendSlice(allocator, "}\n");
}

fn emitInterpolationUpdate(
    interp: browser_render_tree.InterpolationNode,
    bindings_json: []const u8,
    out: *std.ArrayList(u8),
    allocator: std.mem.Allocator,
    indent: usize,
    scope_expr: []const u8,
    refs_expr: []const u8,
) !void {
    try js_output.writeIndent(indent, out, allocator);
    try out.print(allocator, "const __next_text_{d} = String((", .{interp.ref_id});
    try expressions.emitResolvedExpression(interp.expression, scope_expr, bindings_json, out, allocator);
    try out.appendSlice(allocator, ") ?? \"\");\n");
    try js_output.writeIndent(indent, out, allocator);
    try out.print(allocator, "if ({s}[{d}].data !== __next_text_{d}) {{\n", .{
        refs_expr,
        interp.ref_id,
        interp.ref_id,
    });
    try js_output.writeIndent(indent + 1, out, allocator);
    try out.print(allocator, "{s}[{d}].data = __next_text_{d};\n", .{
        refs_expr,
        interp.ref_id,
        interp.ref_id,
    });
    try js_output.writeIndent(indent, out, allocator);
    try out.appendSlice(allocator, "}\n");
}

fn emitBoundAttributeUpdate(
    target_name: []const u8,
    expression: []const u8,
    static_value: ?[]const u8,
    refs_expr: []const u8,
    ref_id: usize,
    scope_expr: []const u8,
    bindings_json: []const u8,
    indent: usize,
    out: *std.ArrayList(u8),
    allocator: std.mem.Allocator,
) !void {
    const suffix = try sanitizedIdentifierFragment(target_name, allocator);
    defer allocator.free(suffix);

    if (std.mem.eql(u8, target_name, "class") and static_value != null) {
        try js_output.writeIndent(indent, out, allocator);
        try out.print(allocator, "const __value_{d}_{s} = ", .{ ref_id, suffix });
        try expressions.emitResolvedExpression(expression, scope_expr, bindings_json, out, allocator);
        try out.appendSlice(allocator, ";\n");
        try js_output.writeIndent(indent, out, allocator);
        try out.print(allocator, "const __static_{d}_{s} = ", .{ ref_id, suffix });
        try js_output.emitHtmlString(static_value.?, out, allocator);
        try out.appendSlice(allocator, ".trim();\n");
        try js_output.writeIndent(indent, out, allocator);
        try out.print(allocator, "const __dynamic_{d}_{s} = __value_{d}_{s} === false || __value_{d}_{s} === true || __value_{d}_{s} === null || __value_{d}_{s} === undefined ? \"\" : String(__value_{d}_{s}).trim();\n", .{
            ref_id,
            suffix,
            ref_id,
            suffix,
            ref_id,
            suffix,
            ref_id,
            suffix,
            ref_id,
            suffix,
            ref_id,
            suffix,
        });
        try js_output.writeIndent(indent, out, allocator);
        try out.print(allocator, "const __next_{d}_{s} = [__static_{d}_{s}, __dynamic_{d}_{s}].filter(Boolean).join(\" \");\n", .{
            ref_id,
            suffix,
            ref_id,
            suffix,
            ref_id,
            suffix,
        });
        try js_output.writeIndent(indent, out, allocator);
        try out.print(allocator, "if (__next_{d}_{s}) {{\n", .{ ref_id, suffix });
        try js_output.writeIndent(indent + 1, out, allocator);
        try out.print(allocator, "{s}[{d}].setAttribute(\"class\", __next_{d}_{s});\n", .{ refs_expr, ref_id, ref_id, suffix });
        try js_output.writeIndent(indent, out, allocator);
        try out.appendSlice(allocator, "} else if (");
        try out.print(allocator, "{s}[{d}].hasAttribute(\"class\")) {{\n", .{ refs_expr, ref_id });
        try js_output.writeIndent(indent + 1, out, allocator);
        try out.print(allocator, "{s}[{d}].removeAttribute(\"class\");\n", .{ refs_expr, ref_id });
        try js_output.writeIndent(indent, out, allocator);
        try out.appendSlice(allocator, "}\n");
        return;
    }

    if (std.mem.eql(u8, target_name, "checked") or
        std.mem.eql(u8, target_name, "disabled") or
        std.mem.eql(u8, target_name, "selected"))
    {
        try js_output.writeIndent(indent, out, allocator);
        try out.print(allocator, "const __value_{d}_{s} = ", .{ ref_id, suffix });
        try expressions.emitResolvedExpression(expression, scope_expr, bindings_json, out, allocator);
        try out.appendSlice(allocator, ";\n");
        try js_output.writeIndent(indent, out, allocator);
        try out.print(allocator, "const __next_{d}_{s} = Boolean(__value_{d}_{s});\n", .{
            ref_id,
            suffix,
            ref_id,
            suffix,
        });
        try js_output.writeIndent(indent, out, allocator);
        try out.print(allocator, "if ({s}[{d}].{s} !== __next_{d}_{s}) {{\n", .{
            refs_expr,
            ref_id,
            target_name,
            ref_id,
            suffix,
        });
        try js_output.writeIndent(indent + 1, out, allocator);
        try out.print(allocator, "{s}[{d}].{s} = __next_{d}_{s};\n", .{
            refs_expr,
            ref_id,
            target_name,
            ref_id,
            suffix,
        });
        try js_output.writeIndent(indent, out, allocator);
        try out.appendSlice(allocator, "}\n");
        try js_output.writeIndent(indent, out, allocator);
        try out.print(allocator, "const __has_attr_{d}_{s} = {s}[{d}].hasAttribute(\"{s}\");\n", .{
            ref_id,
            suffix,
            refs_expr,
            ref_id,
            target_name,
        });
        try js_output.writeIndent(indent, out, allocator);
        try out.print(allocator, "if (__next_{d}_{s}) {{\n", .{ ref_id, suffix });
        try js_output.writeIndent(indent + 1, out, allocator);
        try out.print(allocator, "if (!__has_attr_{d}_{s}) {{ {s}[{d}].setAttribute(\"{s}\", \"\"); }}\n", .{
            ref_id,
            suffix,
            refs_expr,
            ref_id,
            target_name,
        });
        try js_output.writeIndent(indent, out, allocator);
        try out.appendSlice(allocator, "} else {\n");
        try js_output.writeIndent(indent + 1, out, allocator);
        try out.print(allocator, "if (__has_attr_{d}_{s}) {{ {s}[{d}].removeAttribute(\"{s}\"); }}\n", .{
            ref_id,
            suffix,
            refs_expr,
            ref_id,
            target_name,
        });
        try js_output.writeIndent(indent, out, allocator);
        try out.appendSlice(allocator, "}\n");
        return;
    }

    if (std.mem.eql(u8, target_name, "value")) {
        try js_output.writeIndent(indent, out, allocator);
        try out.print(allocator, "const __value_{d}_{s} = ", .{ ref_id, suffix });
        try expressions.emitResolvedExpression(expression, scope_expr, bindings_json, out, allocator);
        try out.appendSlice(allocator, ";\n");
        try js_output.writeIndent(indent, out, allocator);
        try out.print(allocator, "const __next_{d}_{s} = __value_{d}_{s} ?? \"\";\n", .{ ref_id, suffix, ref_id, suffix });
        try js_output.writeIndent(indent, out, allocator);
        try out.print(allocator, "const __next_string_{d}_{s} = String(__next_{d}_{s});\n", .{
            ref_id,
            suffix,
            ref_id,
            suffix,
        });
        try js_output.writeIndent(indent, out, allocator);
        try out.print(allocator, "if ({s}[{d}].value !== __next_string_{d}_{s}) {{\n", .{
            refs_expr,
            ref_id,
            ref_id,
            suffix,
        });
        try js_output.writeIndent(indent + 1, out, allocator);
        try out.print(allocator, "{s}[{d}].value = __next_string_{d}_{s};\n", .{
            refs_expr,
            ref_id,
            ref_id,
            suffix,
        });
        try js_output.writeIndent(indent, out, allocator);
        try out.appendSlice(allocator, "}\n");
        try js_output.writeIndent(indent, out, allocator);
        try out.print(allocator, "{s}[{d}].setAttribute(\"value\", __next_string_{d}_{s});\n", .{
            refs_expr,
            ref_id,
            ref_id,
            suffix,
        });
        return;
    }

    if (std.mem.eql(u8, target_name, "style")) {
        try js_output.writeIndent(indent, out, allocator);
        try out.print(allocator, "const __value_{d}_{s} = ", .{ ref_id, suffix });
        try expressions.emitResolvedExpression(expression, scope_expr, bindings_json, out, allocator);
        try out.appendSlice(allocator, ";\n");
        try js_output.writeIndent(indent, out, allocator);
        try out.print(allocator, "if (__value_{d}_{s} === false || __value_{d}_{s} === null || __value_{d}_{s} === undefined) {{\n", .{
            ref_id,
            suffix,
            ref_id,
            suffix,
            ref_id,
            suffix,
        });
        try js_output.writeIndent(indent + 1, out, allocator);
        try out.print(allocator, "if ({s}[{d}].hasAttribute(\"style\")) {{ {s}[{d}].removeAttribute(\"style\"); }}\n", .{
            refs_expr,
            ref_id,
            refs_expr,
            ref_id,
        });
        try js_output.writeIndent(indent, out, allocator);
        try out.appendSlice(allocator, "} else {\n");
        try js_output.writeIndent(indent + 1, out, allocator);
        try out.print(allocator, "{s}[{d}].style.cssText = __value_{d}_{s} === true ? \"\" : String(__value_{d}_{s});\n", .{
            refs_expr,
            ref_id,
            ref_id,
            suffix,
            ref_id,
            suffix,
        });
        try js_output.writeIndent(indent, out, allocator);
        try out.appendSlice(allocator, "}\n");
        return;
    }

    if (std.mem.startsWith(u8, target_name, "aria-")) {
        try js_output.writeIndent(indent, out, allocator);
        try out.print(allocator, "const __value_{d}_{s} = ", .{ ref_id, suffix });
        try expressions.emitResolvedExpression(expression, scope_expr, bindings_json, out, allocator);
        try out.appendSlice(allocator, ";\n");
        try js_output.writeIndent(indent, out, allocator);
        try out.print(allocator, "if (__value_{d}_{s} === null || __value_{d}_{s} === undefined) {{\n", .{ ref_id, suffix, ref_id, suffix });
        try js_output.writeIndent(indent + 1, out, allocator);
        try out.print(allocator, "{s}[{d}].removeAttribute(\"{s}\");\n", .{ refs_expr, ref_id, target_name });
        try js_output.writeIndent(indent, out, allocator);
        try out.appendSlice(allocator, "} else {\n");
        try js_output.writeIndent(indent + 1, out, allocator);
        try out.print(allocator, "{s}[{d}].setAttribute(\"{s}\", String(__value_{d}_{s}));\n", .{ refs_expr, ref_id, target_name, ref_id, suffix });
        try js_output.writeIndent(indent, out, allocator);
        try out.appendSlice(allocator, "}\n");
        return;
    }

    try js_output.writeIndent(indent, out, allocator);
    try out.print(allocator, "const __value_{d}_{s} = ", .{ ref_id, suffix });
    try expressions.emitResolvedExpression(expression, scope_expr, bindings_json, out, allocator);
    try out.appendSlice(allocator, ";\n");
    try js_output.writeIndent(indent, out, allocator);
    try out.print(allocator, "if (__value_{d}_{s} === false || __value_{d}_{s} === null || __value_{d}_{s} === undefined) {{\n", .{
        ref_id,
        suffix,
        ref_id,
        suffix,
        ref_id,
        suffix,
    });
    try js_output.writeIndent(indent + 1, out, allocator);
    try out.print(allocator, "if ({s}[{d}].hasAttribute(\"{s}\")) {{ {s}[{d}].removeAttribute(\"{s}\"); }}\n", .{
        refs_expr,
        ref_id,
        target_name,
        refs_expr,
        ref_id,
        target_name,
    });
    try js_output.writeIndent(indent, out, allocator);
    try out.print(allocator, "}} else if (__value_{d}_{s} === true) {{\n", .{ ref_id, suffix });
    try js_output.writeIndent(indent + 1, out, allocator);
    try out.print(allocator, "if (!{s}[{d}].hasAttribute(\"{s}\")) {{ {s}[{d}].setAttribute(\"{s}\", \"\"); }}\n", .{
        refs_expr,
        ref_id,
        target_name,
        refs_expr,
        ref_id,
        target_name,
    });
    try js_output.writeIndent(indent, out, allocator);
    try out.appendSlice(allocator, "} else {\n");
    try js_output.writeIndent(indent + 1, out, allocator);
    try out.print(allocator, "{s}[{d}].setAttribute(\"{s}\", String(__value_{d}_{s}));\n", .{
        refs_expr,
        ref_id,
        target_name,
        ref_id,
        suffix,
    });
    try js_output.writeIndent(indent, out, allocator);
    try out.appendSlice(allocator, "}\n");
}

fn sanitizedIdentifierFragment(value: []const u8, allocator: std.mem.Allocator) ![]u8 {
    var out = std.ArrayList(u8).empty;
    defer out.deinit(allocator);

    for (value, 0..) |ch, idx| {
        if ((idx == 0 and std.ascii.isAlphabetic(ch)) or
            (idx > 0 and (std.ascii.isAlphanumeric(ch) or ch == '_')))
        {
            try out.append(allocator, ch);
        } else if (idx == 0 and ch == '_') {
            try out.append(allocator, ch);
        } else {
            try out.append(allocator, '_');
        }
    }

    if (out.items.len == 0) {
        try out.appendSlice(allocator, "value");
    }

    return try out.toOwnedSlice(allocator);
}
