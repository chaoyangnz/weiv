const std = @import("std");
const tree = @import("tree.zig");
const lower_pass = @import("lower.zig");

pub const UnsupportedNodeKind = tree.UnsupportedNodeKind;
pub const TextNode = tree.TextNode;
pub const InterpolationNode = tree.InterpolationNode;
pub const ElementNode = tree.ElementNode;
pub const ConditionalNode = tree.ConditionalNode;
pub const ForLoopNode = tree.ForLoopNode;
pub const ComponentNode = tree.ComponentNode;
pub const SlotOutletNode = tree.SlotOutletNode;
pub const NodeTag = tree.NodeTag;
pub const Node = tree.Node;
pub const Document = tree.Document;

pub fn lower(document: *const @import("../../../lower/lir.zig").Document, allocator: std.mem.Allocator) anyerror!Document {
    return try lower_pass.lower(document, allocator);
}
