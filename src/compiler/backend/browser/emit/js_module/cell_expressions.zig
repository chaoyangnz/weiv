const std = @import("std");
const tree = @import("../../render_tree/types.zig");
const lir = @import("../../../../lower/lir.zig");
const functions = @import("../../../../project/template_functions.zig");
const backend = @import("../../../../../ffi/script_backend.zig");

// Own an emission-only tree in an arena. Dependency regions continue using the
// original expressions; evaluator closures are lowered with the script's symbols.
pub const Plan = struct {
    allocator: std.mem.Allocator,
    evaluators: std.ArrayList(u8) = .empty,
    locals: std.ArrayList([]const u8) = .empty,
    script_names: []const []const u8,
    next: usize = 0,

    fn expression(self: *Plan, source: []const u8, argument: ?[]const u8) ![]const u8 {
        if (argument == null) try backend.validateCellExpression(source, self.allocator) else try backend.validateCellHandlerExpression(source, self.allocator);
        const id = self.next;
        self.next += 1;
        if (id != 0) try self.evaluators.append(self.allocator, ',');
        _ = try functions.append(&self.evaluators, source, self.locals.items, self.script_names, argument, self.allocator);
        return std.fmt.allocPrint(self.allocator, "\x00weiv:{d}:{s}", .{ id, argument orelse "render" });
    }

    fn effects(self: *Plan, source: []lir.DirectiveEffect, argument: ?[]const u8) ![]lir.DirectiveEffect {
        const result = try self.allocator.dupe(lir.DirectiveEffect, source);
        for (result) |*effect| switch (effect.*) {
            .bind => |*binding| binding.expression = try self.expression(binding.expression, null),
            .event => |*event| event.expression = try self.expression(event.expression, argument),
        };
        return result;
    }

    pub fn nodes(self: *Plan, source: []tree.Node) anyerror![]tree.Node {
        const result = try self.allocator.dupe(tree.Node, source);
        for (result) |*node| switch (node.*) {
            .text => {},
            .interpolation => |*value| value.expression = try self.expression(value.expression, null),
            .element => |*value| {
                value.bind_effects = try self.effects(value.bind_effects, null);
                value.event_effects = try self.effects(value.event_effects, "event");
                value.children = try self.nodes(value.children);
            },
            .conditional => |*value| {
                value.condition = try self.expression(value.condition, null);
                value.consequent = try self.nodes(value.consequent);
                value.alternate = try self.nodes(value.alternate);
            },
            .for_loop => |*value| {
                value.iterable_expr = try self.expression(value.iterable_expr, null);
                try self.locals.append(self.allocator, value.item_name);
                defer _ = self.locals.pop();
                value.body = try self.nodes(value.body);
            },
            .slot_outlet => |*value| value.fallback_children = try self.nodes(value.fallback_children),
            .component => |*value| {
                value.bind_effects = try self.effects(value.bind_effects, null);
                value.event_effects = try self.effects(value.event_effects, "payload");
                value.slot_provisions = try self.allocator.dupe(tree.SlotProvision, value.slot_provisions);
                for (value.slot_provisions) |*slot| slot.children = try self.nodes(slot.children);
            },
        };
        return result;
    }
};
