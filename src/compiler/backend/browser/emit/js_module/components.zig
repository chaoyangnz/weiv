const std = @import("std");
const browser_render_tree = @import("../../render_tree/index.zig");
const lir = @import("../../../../lower/lir.zig");
const expressions = @import("expressions.zig");

pub fn componentHasProps(component_node: browser_render_tree.ComponentNode) bool {
    return component_node.bind_effects.len > 0;
}

pub fn componentHasEventHandlers(component_node: browser_render_tree.ComponentNode) bool {
    return component_node.event_effects.len > 0;
}

pub fn componentHasSlots(component_node: browser_render_tree.ComponentNode) bool {
    return component_node.slot_provisions.len > 0;
}

pub fn componentNeedsParentUpdate(component_node: browser_render_tree.ComponentNode) bool {
    return componentHasProps(component_node) or componentHasSlots(component_node);
}

pub fn emitPropsObject(
    effects: []const lir.DirectiveEffect,
    out: *std.ArrayList(u8),
    allocator: std.mem.Allocator,
    scope_expr: []const u8,
    bindings_json: []const u8,
) !void {
    try out.appendSlice(allocator, "{");
    for (effects, 0..) |effect, idx| {
        switch (effect) {
            .bind => |bind_dir| {
                if (idx > 0) try out.appendSlice(allocator, ", ");
                try out.print(allocator, "\"{s}\": ", .{bind_dir.target_name});
                try expressions.emitResolvedExpression(bind_dir.expression, scope_expr, bindings_json, out, allocator);
            },
            .event => unreachable,
        }
    }
    try out.appendSlice(allocator, "}");
}

pub fn emitChildHandlersObject(
    effects: []const lir.DirectiveEffect,
    out: *std.ArrayList(u8),
    allocator: std.mem.Allocator,
    scope_expr: []const u8,
    bindings_json: []const u8,
) !void {
    try out.appendSlice(allocator, "{");
    for (effects, 0..) |effect, idx| {
        switch (effect) {
            .event => |event_dir| {
                if (idx > 0) try out.appendSlice(allocator, ", ");
                try out.print(allocator, "\"{s}\": (payload) => {{ const resolved = ", .{event_dir.event_name});
                try expressions.emitResolvedExpression(event_dir.expression, scope_expr, bindings_json, out, allocator);
                try out.appendSlice(allocator, if (expressions.isCellExpression(event_dir.expression)) "; return resolved; }" else "; if (typeof resolved === \"function\") { return resolved(payload); } return resolved; }");
            },
            .bind => unreachable,
        }
    }
    try out.appendSlice(allocator, "}");
}
