const std = @import("std");
const tree = @import("../backend/browser/render_tree/tree.zig");

pub fn formatDocument(document: *const tree.Document, allocator: std.mem.Allocator) ![]u8 {
    var out = std.ArrayList(u8).empty;
    defer out.deinit(allocator);

    try out.print(allocator, "render-tree next_ref_id={d}\n", .{document.next_ref_id});
    try formatNodes(document.nodes, 0, &out, allocator);
    return try out.toOwnedSlice(allocator);
}

fn formatNodes(
    nodes: []const tree.Node,
    indent: usize,
    out: *std.ArrayList(u8),
    allocator: std.mem.Allocator,
) !void {
    for (nodes) |node| {
        try writeIndent(indent, out, allocator);
        switch (node) {
            .text => |text| try out.print(allocator, "text {s}\n", .{text.content}),
            .interpolation => |interp| try out.print(allocator, "interpolation ref={d} expr={s}\n", .{
                interp.ref_id,
                interp.expression,
            }),
            .element => |element| {
                try out.print(allocator, "element ref={d} <{s}> attrs={d} binds={d} events={d}\n", .{
                    element.ref_id,
                    element.tag_name,
                    element.attributes.len,
                    element.bind_effects.len,
                    element.event_effects.len,
                });
                try formatNodes(element.children, indent + 1, out, allocator);
            },
            .conditional => |conditional| {
                try out.print(allocator, "conditional refs=[{d},{d}] state={d} if={s}\n", .{
                    conditional.start_ref_id,
                    conditional.end_ref_id,
                    conditional.state_ref_id,
                    conditional.condition,
                });
                try writeIndent(indent + 1, out, allocator);
                try out.appendSlice(allocator, "consequent\n");
                try formatNodes(conditional.consequent, indent + 2, out, allocator);
                try writeIndent(indent + 1, out, allocator);
                try out.appendSlice(allocator, "alternate\n");
                try formatNodes(conditional.alternate, indent + 2, out, allocator);
            },
            .for_loop => |for_loop| {
                try out.print(allocator, "for-loop refs=[{d},{d}] state={d} item={s} in={s}\n", .{
                    for_loop.start_ref_id,
                    for_loop.end_ref_id,
                    for_loop.state_ref_id,
                    for_loop.item_name,
                    for_loop.iterable_expr,
                });
                try formatNodes(for_loop.body, indent + 1, out, allocator);
            },
            .component => |component| {
                try out.print(allocator, "component refs=[{d},{d}] handle={d} <{s}> binds={d} events={d} slots={d}\n", .{
                    component.start_ref_id,
                    component.end_ref_id,
                    component.handle_ref_id,
                    component.tag_name,
                    component.bind_effects.len,
                    component.event_effects.len,
                    component.slot_provisions.len,
                });
                for (component.slot_provisions) |slot_provision| {
                    try writeIndent(indent + 1, out, allocator);
                    if (slot_provision.name) |name| {
                        try out.print(allocator, "slot-provision name={s}\n", .{name});
                    } else {
                        try out.appendSlice(allocator, "slot-provision name=default\n");
                    }
                    try formatNodes(slot_provision.children, indent + 2, out, allocator);
                }
            },
            .slot_outlet => |slot_outlet| {
                try out.print(allocator, "slot-outlet refs=[{d},{d}] handle={d} name=", .{
                    slot_outlet.start_ref_id,
                    slot_outlet.end_ref_id,
                    slot_outlet.handle_ref_id,
                });
                if (slot_outlet.name) |name| {
                    try out.print(allocator, "{s}\n", .{name});
                } else {
                    try out.appendSlice(allocator, "default\n");
                }
                try formatNodes(slot_outlet.fallback_children, indent + 1, out, allocator);
            },
        }
    }
}

fn writeIndent(indent: usize, out: *std.ArrayList(u8), allocator: std.mem.Allocator) !void {
    for (0..indent) |_| {
        try out.appendSlice(allocator, "  ");
    }
}
