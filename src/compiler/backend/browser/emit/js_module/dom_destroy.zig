const std = @import("std");
const browser_render_tree = @import("../../render_tree/index.zig");
const common = @import("common.zig");

pub fn emitDestroyFunction(
    render_tree: browser_render_tree.Document,
    out: *std.ArrayList(u8),
    allocator: std.mem.Allocator,
) !void {
    try out.appendSlice(allocator,
        \\function destroyDom(instance) {
        \\  const refs = instance.refs;
        \\
    );
    for (render_tree.nodes) |node| {
        try emitDestroyNode(node, out, allocator, 1, "refs");
    }
    try out.appendSlice(allocator,
        \\}
        \\
    );
}

pub fn emitDestroyNode(
    node: browser_render_tree.Node,
    out: *std.ArrayList(u8),
    allocator: std.mem.Allocator,
    indent: usize,
    refs_expr: []const u8,
) !void {
    switch (node) {
        .text, .interpolation => {},
        .element => |element| {
            for (element.children) |child| {
                try emitDestroyNode(child, out, allocator, indent, refs_expr);
            }
        },
        .slot_outlet => |slot_outlet| {
            const current_slot_var_name = try std.fmt.allocPrint(allocator, "__destroy_slot_{d}", .{slot_outlet.handle_ref_id});
            defer allocator.free(current_slot_var_name);
            try common.writeIndent(indent, out, allocator);
            try out.print(allocator, "const {s} = {s}[{d}];\n", .{
                current_slot_var_name,
                refs_expr,
                slot_outlet.handle_ref_id,
            });
            try common.writeIndent(indent, out, allocator);
            try out.print(allocator, "if ({s} && {s} !== false && typeof {s}.destroy === \"function\") {{\n", .{
                current_slot_var_name,
                current_slot_var_name,
                current_slot_var_name,
            });
            try common.writeIndent(indent + 1, out, allocator);
            try out.print(allocator, "{s}.destroy();\n", .{current_slot_var_name});
            try common.writeIndent(indent, out, allocator);
            try out.appendSlice(allocator, "} else {\n");
            for (slot_outlet.fallback_children) |child| {
                try emitDestroyNode(child, out, allocator, indent + 1, refs_expr);
            }
            try common.writeIndent(indent, out, allocator);
            try out.appendSlice(allocator, "}\n");
        },
        .conditional => |conditional| {
            try common.writeIndent(indent, out, allocator);
            try out.print(allocator, "if ({s}[{d}] === true) {{\n", .{ refs_expr, conditional.state_ref_id });
            for (conditional.consequent) |child| {
                try emitDestroyNode(child, out, allocator, indent + 1, refs_expr);
            }
            try common.writeIndent(indent, out, allocator);
            try out.appendSlice(allocator, "} else {\n");
            for (conditional.alternate) |child| {
                try emitDestroyNode(child, out, allocator, indent + 1, refs_expr);
            }
            try common.writeIndent(indent, out, allocator);
            try out.appendSlice(allocator, "}\n");
        },
        .component => |component_node| {
            try common.writeIndent(indent, out, allocator);
            try out.print(allocator, "if ({s}[{d}] && typeof {s}[{d}].destroy === \"function\") {{\n", .{
                refs_expr,
                component_node.handle_ref_id,
                refs_expr,
                component_node.handle_ref_id,
            });
            try common.writeIndent(indent + 1, out, allocator);
            try out.print(allocator, "{s}[{d}].destroy();\n", .{ refs_expr, component_node.handle_ref_id });
            try common.writeIndent(indent, out, allocator);
            try out.appendSlice(allocator, "}\n");
            try common.writeIndent(indent, out, allocator);
            try out.print(allocator, "{s}[{d}] = undefined;\n", .{ refs_expr, component_node.handle_ref_id });
        },
        .for_loop => |for_loop| {
            const records_var_name = try std.fmt.allocPrint(allocator, "__records_{d}", .{for_loop.state_ref_id});
            defer allocator.free(records_var_name);
            try common.writeIndent(indent, out, allocator);
            try out.print(allocator, "const {s} = {s}[{d}] ?? [];\n", .{
                records_var_name,
                refs_expr,
                for_loop.state_ref_id,
            });
            try common.writeIndent(indent, out, allocator);
            try out.print(allocator, "for (const record of {s}) {{\n", .{records_var_name});
            try common.writeIndent(indent + 1, out, allocator);
            try out.appendSlice(allocator, "if (record.handle && typeof record.handle.destroy === \"function\") {\n");
            try common.writeIndent(indent + 2, out, allocator);
            try out.appendSlice(allocator, "record.handle.destroy();\n");
            try common.writeIndent(indent + 1, out, allocator);
            try out.appendSlice(allocator, "} else if (typeof record.destroy === \"function\") {\n");
            try common.writeIndent(indent + 2, out, allocator);
            try out.appendSlice(allocator, "record.destroy();\n");
            try common.writeIndent(indent + 1, out, allocator);
            try out.appendSlice(allocator, "}\n");
            try common.writeIndent(indent, out, allocator);
            try out.appendSlice(allocator, "}\n");
        },
    }
}
