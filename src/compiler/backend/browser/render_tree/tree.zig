const std = @import("std");
const lir = @import("../../../lower/lir.zig");

pub const UnsupportedNodeKind = error{};

pub const TextNode = struct {
    content: []const u8,
};

pub const InterpolationNode = struct {
    ref_id: usize,
    expression: []const u8,
};

pub const ElementNode = struct {
    ref_id: usize,
    tag_name: []const u8,
    /// Borrowed from LIR; the ComponentUnit must outlive this tree.
    attributes: []lir.Attribute,
    /// The slices are owned by this tree; expression text inside them is borrowed.
    bind_effects: []lir.DirectiveEffect,
    event_effects: []lir.DirectiveEffect,
    children: []Node,
};

pub const ConditionalNode = struct {
    condition: []const u8,
    start_ref_id: usize,
    end_ref_id: usize,
    state_ref_id: usize,
    consequent: []Node,
    alternate: []Node,
};

pub const ForLoopNode = struct {
    item_name: []const u8,
    iterable_expr: []const u8,
    start_ref_id: usize,
    end_ref_id: usize,
    state_ref_id: usize,
    body: []Node,
};

pub const ComponentNode = struct {
    tag_name: []const u8,
    start_ref_id: usize,
    end_ref_id: usize,
    handle_ref_id: usize,
    bind_effects: []lir.DirectiveEffect,
    event_effects: []lir.DirectiveEffect,
    slot_provisions: []SlotProvision,
};

pub const SlotOutletNode = struct {
    name: ?[]const u8,
    start_ref_id: usize,
    end_ref_id: usize,
    handle_ref_id: usize,
    fallback_children: []Node,
};

pub const SlotProvision = struct {
    name: ?[]const u8,
    children: []Node,
};

pub const NodeTag = enum {
    element,
    text,
    interpolation,
    conditional,
    for_loop,
    component,
    slot_outlet,
};

pub const Node = union(NodeTag) {
    element: ElementNode,
    text: TextNode,
    interpolation: InterpolationNode,
    conditional: ConditionalNode,
    for_loop: ForLoopNode,
    component: ComponentNode,
    slot_outlet: SlotOutletNode,

    pub fn deinit(self: *Node, allocator: std.mem.Allocator) void {
        switch (self.*) {
            .element => |*element| {
                allocator.free(element.bind_effects);
                allocator.free(element.event_effects);
                for (element.children) |*child| child.deinit(allocator);
                allocator.free(element.children);
            },
            .conditional => |*conditional| {
                for (conditional.consequent) |*child| child.deinit(allocator);
                allocator.free(conditional.consequent);
                for (conditional.alternate) |*child| child.deinit(allocator);
                allocator.free(conditional.alternate);
            },
            .for_loop => |*for_loop| {
                for (for_loop.body) |*child| child.deinit(allocator);
                allocator.free(for_loop.body);
            },
            .component => |*component| {
                allocator.free(component.bind_effects);
                allocator.free(component.event_effects);
                for (component.slot_provisions) |*slot_provision| {
                    for (slot_provision.children) |*child| child.deinit(allocator);
                    allocator.free(slot_provision.children);
                }
                allocator.free(component.slot_provisions);
            },
            .slot_outlet => |*slot_outlet| {
                for (slot_outlet.fallback_children) |*child| child.deinit(allocator);
                allocator.free(slot_outlet.fallback_children);
            },
            .text, .interpolation => {},
        }
    }
};

pub const Document = struct {
    /// Owns node/effect arrays, but borrows source text and attributes from LIR.
    nodes: []Node,
    next_ref_id: usize,

    pub fn deinit(self: *Document, allocator: std.mem.Allocator) void {
        for (self.nodes) |*node| node.deinit(allocator);
        allocator.free(self.nodes);
        self.* = undefined;
    }
};
