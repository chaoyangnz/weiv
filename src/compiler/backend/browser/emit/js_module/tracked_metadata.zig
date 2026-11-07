const std = @import("std");
const region_graph = @import("../../region_graph.zig");
const js_output = @import("output.zig");

pub fn emitTrackedStateGraphMetadata(graph: *const region_graph.Graph, out: *std.ArrayList(u8), allocator: std.mem.Allocator) !void {
    try out.appendSlice(allocator, "export const trackedStateGraph = ");
    try emitTrackedStateGraphObject(graph, out, allocator);
    try out.appendSlice(allocator, ";\n");
}

fn emitTrackedStateGraphObject(
    graph: *const region_graph.Graph,
    out: *std.ArrayList(u8),
    allocator: std.mem.Allocator,
) !void {
    try out.appendSlice(allocator, "{ roots: [");
    for (graph.table.roots.items, 0..) |root, idx| {
        if (idx > 0) try out.appendSlice(allocator, ", ");
        try out.print(allocator, "{{ rootId: {d}, bindingName: ", .{root.id});
        try js_output.emitString(root.binding_name, out, allocator);
        try out.appendSlice(allocator, ", kind: \"");
        try out.appendSlice(allocator, root.kind);
        try out.appendSlice(allocator, "\" }");
    }
    try out.appendSlice(allocator, "], paths: [");
    for (graph.table.paths.items, 0..) |path, idx| {
        if (idx > 0) try out.appendSlice(allocator, ", ");
        try out.print(allocator, "{{ pathId: {d}, rootId: {d}, path: ", .{ path.id, path.root_id });
        try js_output.emitString(path.path, out, allocator);
        if (path.parent_path_id) |parent_id| {
            try out.print(allocator, ", parentPathId: {d} }}", .{parent_id});
        } else {
            try out.appendSlice(allocator, ", parentPathId: null }");
        }
    }
    try out.appendSlice(allocator, "], regions: [");
    var wrote_region = false;
    for (graph.regions.items) |region| {
        if (region.tracked_path_ids.items.len == 0) continue;
        if (wrote_region) try out.appendSlice(allocator, ", ");
        try out.print(allocator, "{{ regionId: {d}, trackedPathIds: [", .{region.id});
        for (region.tracked_path_ids.items, 0..) |path_id, path_idx| {
            if (path_idx > 0) try out.appendSlice(allocator, ", ");
            try out.print(allocator, "{d}", .{path_id});
        }
        try out.appendSlice(allocator, "] }");
        wrote_region = true;
    }
    try out.appendSlice(allocator, "] }");
}
