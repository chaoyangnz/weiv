const std = @import("std");
const lir = @import("../../../lower/lir.zig");
const effects = @import("effects.zig");
const tree = @import("tree.zig");

const Lowerer = struct {
    allocator: std.mem.Allocator,
    next_ref_id: usize = 0,

    fn nextRefId(self: *Lowerer) usize {
        const id = self.next_ref_id;
        self.next_ref_id += 1;
        return id;
    }

    fn lowerNodes(self: *Lowerer, nodes: []const lir.Node) anyerror![]tree.Node {
        var out = std.ArrayList(tree.Node).empty;
        defer out.deinit(self.allocator);

        for (nodes) |node| {
            try out.append(self.allocator, try self.lowerNode(node));
        }

        return try out.toOwnedSlice(self.allocator);
    }

    fn lowerNode(self: *Lowerer, node: lir.Node) anyerror!tree.Node {
        return switch (node) {
            .text => |text| .{
                .text = .{ .content = text.content },
            },
            .interpolation => |interp| .{
                .interpolation = .{
                    .ref_id = self.nextRefId(),
                    .expression = interp.expression,
                },
            },
            .slot_outlet => |slot_outlet| .{
                .slot_outlet = .{
                    .name = slot_outlet.name,
                    .start_ref_id = self.nextRefId(),
                    .end_ref_id = self.nextRefId(),
                    .handle_ref_id = self.nextRefId(),
                    .fallback_children = try self.lowerNodes(slot_outlet.fallback_children),
                },
            },
            .element => |element| blk: {
                const bind_effects = try effects.splitEffects(self.allocator, element.effects, .bind);
                errdefer self.allocator.free(bind_effects);
                const event_effects = try effects.splitEffects(self.allocator, element.effects, .event);
                errdefer self.allocator.free(event_effects);
                const children = try self.lowerNodes(element.children);
                errdefer {
                    for (children) |*child| child.deinit(self.allocator);
                    self.allocator.free(children);
                }
                break :blk .{
                    .element = .{
                        .ref_id = self.nextRefId(),
                        .tag_name = element.tag_name,
                        .attributes = element.attributes,
                        .bind_effects = bind_effects,
                        .event_effects = event_effects,
                        .children = children,
                    },
                };
            },
            .conditional => |conditional| .{
                .conditional = .{
                    .condition = conditional.condition,
                    .start_ref_id = self.nextRefId(),
                    .end_ref_id = self.nextRefId(),
                    .state_ref_id = self.nextRefId(),
                    .consequent = try self.lowerNodes(conditional.consequent),
                    .alternate = try self.lowerNodes(conditional.alternate),
                },
            },
            .for_loop => |for_loop| .{
                .for_loop = .{
                    .item_name = for_loop.item_name,
                    .iterable_expr = for_loop.iterable_expr,
                    .start_ref_id = self.nextRefId(),
                    .end_ref_id = self.nextRefId(),
                    .state_ref_id = self.nextRefId(),
                    .body = try self.lowerNodes(for_loop.body),
                },
            },
            .component => |component| blk: {
                const bind_effects = try effects.splitEffects(self.allocator, component.effects, .bind);
                errdefer self.allocator.free(bind_effects);
                const event_effects = try effects.splitEffects(self.allocator, component.effects, .event);
                errdefer self.allocator.free(event_effects);
                const slot_provisions = try self.lowerSlotProvisions(component.slot_provisions);
                errdefer freeSlotProvisions(slot_provisions, self.allocator);
                break :blk .{
                    .component = .{
                        .tag_name = component.tag_name,
                        .start_ref_id = self.nextRefId(),
                        .end_ref_id = self.nextRefId(),
                        .handle_ref_id = self.nextRefId(),
                        .bind_effects = bind_effects,
                        .event_effects = event_effects,
                        .slot_provisions = slot_provisions,
                    },
                };
            },
        };
    }

    fn lowerSlotProvisions(self: *Lowerer, provisions: []const lir.SlotProvision) anyerror![]tree.SlotProvision {
        var out = std.ArrayList(tree.SlotProvision).empty;
        defer out.deinit(self.allocator);

        for (provisions) |provision| {
            try out.append(self.allocator, .{
                .name = provision.name,
                .children = try self.lowerNodes(provision.children),
            });
        }

        return try out.toOwnedSlice(self.allocator);
    }
};

pub fn lower(document: *const lir.Document, allocator: std.mem.Allocator) anyerror!tree.Document {
    var lowerer = Lowerer{
        .allocator = allocator,
    };
    const nodes = try lowerer.lowerNodes(document.nodes);
    return .{
        .nodes = nodes,
        .next_ref_id = lowerer.next_ref_id,
    };
}

fn freeSlotProvisions(provisions: []tree.SlotProvision, allocator: std.mem.Allocator) void {
    for (provisions) |*provision| {
        for (provision.children) |*child| child.deinit(allocator);
        allocator.free(provision.children);
    }
    allocator.free(provisions);
}
