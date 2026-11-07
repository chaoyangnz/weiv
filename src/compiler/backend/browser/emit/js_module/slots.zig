const std = @import("std");
const browser_render_tree = @import("../../render_tree/index.zig");
const js_output = @import("output.zig");

pub fn emitSlotLookupLine(
    slot_outlet: browser_render_tree.SlotOutletNode,
    var_name: []const u8,
    indent: usize,
    out: *std.ArrayList(u8),
    allocator: std.mem.Allocator,
) !void {
    try js_output.writeIndent(indent, out, allocator);
    if (slot_outlet.name) |name| {
        try out.print(allocator, "const {s} = instance.slots?.[", .{var_name});
        try js_output.emitString(name, out, allocator);
        try out.appendSlice(allocator, "];\n");
    } else {
        try out.print(allocator, "const {s} = instance.slots?.default;\n", .{var_name});
    }
}

pub fn emitSlotFallbackReplaceLine(
    slot_outlet: browser_render_tree.SlotOutletNode,
    start_expr: []const u8,
    end_expr: []const u8,
    scope_expr: []const u8,
    indent: usize,
    out: *std.ArrayList(u8),
    allocator: std.mem.Allocator,
) !void {
    try js_output.writeIndent(indent, out, allocator);
    try out.print(allocator, "replaceBetween({s}, {s}, createSlotFallbackFragment_{d}(instance, {s}));\n", .{
        start_expr,
        end_expr,
        slot_outlet.handle_ref_id,
        scope_expr,
    });
}

pub fn emitProjectedSlotObject(
    component_node: browser_render_tree.ComponentNode,
    owner_instance_expr: []const u8,
    out: *std.ArrayList(u8),
    allocator: std.mem.Allocator,
) !void {
    try out.appendSlice(allocator, "{ ");
    for (component_node.slot_provisions, 0..) |slot_provision, idx| {
        if (idx > 0) try out.appendSlice(allocator, ", ");
        if (slot_provision.name) |name| {
            try js_output.emitString(name, out, allocator);
        } else {
            try out.appendSlice(allocator, "default");
        }
        try out.print(allocator, ": {{ mountIntoBoundary: (start, end) => mountProjectedSlot_{d}_{d}(start, end, {s}) }}", .{
            component_node.handle_ref_id,
            idx,
            owner_instance_expr,
        });
    }
    try out.appendSlice(allocator, " }");
}
