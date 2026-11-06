const std = @import("std");
const component = @import("../../component_unit.zig");
const render_tree = @import("render_tree/index.zig");
const tracked_paths = @import("tracked_paths.zig");
const dependencies = @import("dependencies.zig");

// The regions directly updated by updateDirtyRegions. Structural nodes own
// their descendants, so nested explanatory nodes are not separate regions here.
pub const Region = struct {
    id: usize,
    kind: []const u8,
    ref_id: usize,
    name: ?[]const u8,
    dependency_names: std.ArrayList([]const u8),
    tracked_path_ids: std.ArrayList(usize),
    precise_import_name: ?[]const u8 = null,

    fn deinit(self: *Region, allocator: std.mem.Allocator) void {
        self.dependency_names.deinit(allocator);
        self.tracked_path_ids.deinit(allocator);
    }
};

pub const Graph = struct {
    allocator: std.mem.Allocator,
    table: tracked_paths.Table,
    regions: std.ArrayList(Region) = .empty,
    retain_imported_calls: bool = false,

    pub fn deinit(self: *Graph) void {
        for (self.regions.items) |*item| item.deinit(self.allocator);
        self.regions.deinit(self.allocator);
        self.table.deinit();
    }

    pub fn region(self: *const Graph, id: usize) *const Region {
        return &self.regions.items[id - 1];
    }
};

pub fn build(model: *const component.ComponentUnit, tree: *const render_tree.Document, allocator: std.mem.Allocator) !Graph {
    return buildWithCells(model, tree, true, allocator);
}

pub fn buildWithCells(model: *const component.ComponentUnit, tree: *const render_tree.Document, cells: bool, allocator: std.mem.Allocator) !Graph {
    var graph = Graph{ .allocator = allocator, .table = tracked_paths.Table.init(model, allocator), .retain_imported_calls = cells };
    errdefer graph.deinit();
    try collectNodes(model, tree.nodes, &graph);
    return graph;
}

fn collectNodes(model: *const component.ComponentUnit, nodes: []const render_tree.Node, graph: *Graph) !void {
    for (nodes) |node| {
        switch (node) {
            .text => {},
            .interpolation => |interp| try appendExpression(model, graph, "text", interp.ref_id, null, interp.expression),
            .element => |element| {
                for (element.bind_effects) |effect| {
                    switch (effect) {
                        .bind => |bind| try appendExpression(model, graph, "attribute", element.ref_id, bind.target_name, bind.expression),
                        .event => {},
                    }
                }
                try collectNodes(model, element.children, graph);
            },
            .conditional => |conditional| try appendStructural(model, graph, node, "conditional", conditional.state_ref_id, null, conditional.condition),
            .for_loop => |loop| try appendStructural(model, graph, node, "loop", loop.state_ref_id, loop.item_name, loop.iterable_expr),
            .component => |child| {
                var region = try createRegion(model, graph, "child", child.handle_ref_id, child.tag_name, node);
                errdefer region.deinit(graph.allocator);
                for (child.bind_effects) |effect| {
                    switch (effect) {
                        .bind => |bind| try graph.table.collectExpressionIds(bind.expression, &region.tracked_path_ids),
                        .event => {},
                    }
                }
                for (child.event_effects) |effect| {
                    switch (effect) {
                        .bind => |bind| try graph.table.collectExpressionIds(bind.expression, &region.tracked_path_ids),
                        .event => |event| try graph.table.collectExpressionIds(event.expression, &region.tracked_path_ids),
                    }
                }
                try graph.regions.append(graph.allocator, region);
            },
            .slot_outlet => |slot| {
                var region = try createRegion(model, graph, "slot", slot.handle_ref_id, slot.name, node);
                errdefer region.deinit(graph.allocator);
                try graph.regions.append(graph.allocator, region);
            },
        }
    }
}

fn appendExpression(model: *const component.ComponentUnit, graph: *Graph, kind: []const u8, ref_id: usize, name: ?[]const u8, expr: []const u8) !void {
    var deps = dependencies.DepList{ .retain_imported_calls = graph.retain_imported_calls };
    errdefer deps.deinit(graph.allocator);
    try dependencies.collectExpressionDeps(model, expr, &.{}, &deps, graph.allocator);
    dependencies.retainVisibleBindingDeps(model, &deps);
    var paths = std.ArrayList(usize).empty;
    errdefer paths.deinit(graph.allocator);
    try graph.table.collectExpressionIds(expr, &paths);
    var precise_import_name: ?[]const u8 = null;
    if (deps.items.items.len == 1 and paths.items.len == 1) {
        const path = graph.table.paths.items[paths.items[0] - 1];
        const root = graph.table.roots.items[path.root_id - 1];
        if (std.mem.eql(u8, root.kind, "imported-tracked") and
            std.mem.indexOfAny(u8, path.path, " \t\r\n") == null and
            std.mem.eql(u8, std.mem.trim(u8, expr, &std.ascii.whitespace), path.path) and
            std.mem.eql(u8, deps.items.items[0], root.binding_name))
        {
            precise_import_name = root.binding_name;
        }
    }
    try graph.regions.append(graph.allocator, .{
        .id = graph.regions.items.len + 1,
        .kind = kind,
        .ref_id = ref_id,
        .name = name,
        .dependency_names = deps.items,
        .tracked_path_ids = paths,
        .precise_import_name = precise_import_name,
    });
}

fn appendStructural(model: *const component.ComponentUnit, graph: *Graph, node: render_tree.Node, kind: []const u8, ref_id: usize, name: ?[]const u8, expr: []const u8) !void {
    var region = try createRegion(model, graph, kind, ref_id, name, node);
    errdefer region.deinit(graph.allocator);
    try graph.table.collectExpressionIds(expr, &region.tracked_path_ids);
    try graph.regions.append(graph.allocator, region);
}

fn createRegion(model: *const component.ComponentUnit, graph: *Graph, kind: []const u8, ref_id: usize, name: ?[]const u8, node: render_tree.Node) !Region {
    var deps = dependencies.DepList{ .retain_imported_calls = graph.retain_imported_calls };
    errdefer deps.deinit(graph.allocator);
    try dependencies.collectNodeDeps(model, node, &.{}, &deps, graph.allocator);
    dependencies.retainVisibleBindingDeps(model, &deps);
    return .{
        .id = graph.regions.items.len + 1,
        .kind = kind,
        .ref_id = ref_id,
        .name = name,
        .dependency_names = deps.items,
        .tracked_path_ids = .empty,
    };
}
