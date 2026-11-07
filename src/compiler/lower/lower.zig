const std = @import("std");
const binding = @import("../sema/bind.zig");
const lir = @import("lir.zig");
const template = @import("../parser/template/index.zig");

pub const LowerError = error{
    InvalidSlotPlacement,
    InvalidSlotTemplatePlacement,
};

pub fn lower(
    normalized_template: *const template.NormalizedDocument,
    template_bindings: *const binding.TemplateBindings,
    allocator: std.mem.Allocator,
) anyerror!lir.Document {
    const expressions = try allocator.alloc(lir.ExpressionFacts, template_bindings.expressions.len);
    var initialized: usize = 0;
    errdefer {
        for (expressions[0..initialized]) |expression| allocator.free(expression.references);
        allocator.free(expressions);
    }
    for (template_bindings.expressions, 0..) |expression, index| {
        const references = try allocator.alloc(lir.ExpressionReference, expression.references.len);
        for (expression.references, 0..) |reference, ref_index| {
            references[ref_index] = .{ .name = reference.name, .call = reference.call };
        }
        expressions[index] = .{ .source = expression.source, .references = references };
        initialized += 1;
    }
    return .{
        .nodes = try lowerNodes(normalized_template.nodes, allocator),
        .expressions = expressions,
    };
}

fn lowerNodes(nodes: []const template.NormalizedNode, allocator: std.mem.Allocator) anyerror![]lir.Node {
    var out = std.ArrayList(lir.Node).empty;
    defer out.deinit(allocator);

    for (nodes) |node| {
        try out.append(allocator, try lowerNode(node, allocator));
    }

    return try out.toOwnedSlice(allocator);
}

fn lowerNode(node: template.NormalizedNode, allocator: std.mem.Allocator) anyerror!lir.Node {
    return switch (node) {
        .text => |text| .{
            .text = .{ .content = text.content },
        },
        .interpolation => |interp| .{
            .interpolation = .{ .expression = interp.expression },
        },
        .slot_outlet => |slot_outlet| .{
            .slot_outlet = .{
                .name = slot_outlet.name,
                .fallback_children = try lowerNodes(slot_outlet.fallback_children, allocator),
            },
        },
        .conditional => |conditional| .{
            .conditional = .{
                .condition = conditional.condition,
                .consequent = try lowerNodes(conditional.consequent, allocator),
                .alternate = try lowerNodes(conditional.alternate, allocator),
            },
        },
        .for_loop => |for_loop| .{
            .for_loop = .{
                .item_name = for_loop.item_name,
                .iterable_expr = for_loop.iterable_expr,
                .body = try lowerNodes(for_loop.body, allocator),
            },
        },
        .element => |element| blk: {
            if (std.mem.eql(u8, element.tag_name, "template")) {
                return error.InvalidSlotTemplatePlacement;
            }
            if (extractSlotAssign(.{ .element = element }) != null) {
                return error.InvalidSlotPlacement;
            }
            const effects = try lowerEffects(element.directives, allocator);
            errdefer allocator.free(effects);
            if (isComponentTag(element.tag_name)) {
                const slot_provisions = try lowerSlotProvisions(element.children, allocator);
                errdefer freeSlotProvisions(slot_provisions, allocator);
                break :blk .{
                    .component = .{
                        .tag_name = element.tag_name,
                        .effects = effects,
                        .slot_provisions = slot_provisions,
                    },
                };
            }

            const attributes = try lowerAttributes(element.attributes, allocator);
            errdefer allocator.free(attributes);
            const children = try lowerNodes(element.children, allocator);
            errdefer {
                for (children) |*child| child.deinit(allocator);
                allocator.free(children);
            }
            break :blk .{
                .element = .{
                    .tag_name = element.tag_name,
                    .attributes = attributes,
                    .effects = effects,
                    .children = children,
                },
            };
        },
    };
}

fn lowerEffects(directives: []const template.Directive, allocator: std.mem.Allocator) anyerror![]lir.DirectiveEffect {
    var out = std.ArrayList(lir.DirectiveEffect).empty;
    defer out.deinit(allocator);

    for (directives) |directive| {
        switch (directive) {
            .bind => |bind_dir| try out.append(allocator, .{
                .bind = .{
                    .target_name = bind_dir.target_name,
                    .expression = bind_dir.expression,
                },
            }),
            .event => |event_dir| try out.append(allocator, .{
                .event = .{
                    .event_name = event_dir.event_name,
                    .expression = event_dir.expression,
                },
            }),
            // slot_assign on a non-component element is a binder diagnostic; skip silently here.
            .if_expr, .else_branch, .for_expr => unreachable,
            .slot_assign => {},
        }
    }

    return try out.toOwnedSlice(allocator);
}

fn lowerAttributes(
    attributes: []const template.Attribute,
    allocator: std.mem.Allocator,
) anyerror![]lir.Attribute {
    var out = try allocator.alloc(lir.Attribute, attributes.len);
    for (attributes, 0..) |attribute, idx| {
        out[idx] = .{
            .name = attribute.name,
            .value = attribute.value,
        };
    }
    return out;
}

fn isComponentTag(tag_name: []const u8) bool {
    if (tag_name.len == 0) return false;
    return std.ascii.isUpper(tag_name[0]);
}

fn lowerSlotProvisions(
    children: []const template.NormalizedNode,
    allocator: std.mem.Allocator,
) anyerror![]lir.SlotProvision {
    var out = std.ArrayList(lir.SlotProvision).empty;
    defer out.deinit(allocator);

    for (children) |child| {
        const slot_name = extractSlotAssign(child);
        const lowered_children = try lowerProjectedChildren(child, allocator);
        errdefer {
            for (lowered_children) |*lowered_child| lowered_child.deinit(allocator);
            allocator.free(lowered_children);
        }

        if (findSlotProvision(out.items, slot_name)) |idx| {
            const existing = out.items[idx];
            const merged = try allocator.alloc(lir.Node, existing.children.len + lowered_children.len);
            @memcpy(merged[0..existing.children.len], existing.children);
            @memcpy(merged[existing.children.len..], lowered_children);
            allocator.free(existing.children);
            allocator.free(lowered_children);
            out.items[idx].children = merged;
            continue;
        }

        try out.append(allocator, .{
            .name = slot_name,
            .children = lowered_children,
        });
    }

    return try out.toOwnedSlice(allocator);
}

fn lowerProjectedChildren(child: template.NormalizedNode, allocator: std.mem.Allocator) anyerror![]lir.Node {
    return switch (child) {
        .element => |element| blk: {
            if (std.mem.eql(u8, element.tag_name, "template")) {
                if (extractSlotAssign(child) == null) {
                    return error.InvalidSlotTemplatePlacement;
                }
                break :blk try lowerNodes(element.children, allocator);
            }

            var single = try allocator.alloc(lir.Node, 1);
            errdefer allocator.free(single);
            single[0] = try lowerProjectedElement(element, allocator);
            return single;
        },
        else => {
            var single = try allocator.alloc(lir.Node, 1);
            errdefer allocator.free(single);
            single[0] = try lowerNode(child, allocator);
            return single;
        },
    };
}

fn lowerProjectedElement(element: template.normalized.ElementNode, allocator: std.mem.Allocator) anyerror!lir.Node {
    const filtered_directives = try filterOutSlotAssign(element.directives, allocator);
    defer allocator.free(filtered_directives);

    const effects = try lowerEffects(filtered_directives, allocator);
    errdefer allocator.free(effects);

    if (isComponentTag(element.tag_name)) {
        const slot_provisions = try lowerSlotProvisions(element.children, allocator);
        errdefer freeSlotProvisions(slot_provisions, allocator);
        return .{
            .component = .{
                .tag_name = element.tag_name,
                .effects = effects,
                .slot_provisions = slot_provisions,
            },
        };
    }

    const attributes = try lowerAttributes(element.attributes, allocator);
    errdefer allocator.free(attributes);
    const children = try lowerNodes(element.children, allocator);
    errdefer {
        for (children) |*child| child.deinit(allocator);
        allocator.free(children);
    }
    return .{
        .element = .{
            .tag_name = element.tag_name,
            .attributes = attributes,
            .effects = effects,
            .children = children,
        },
    };
}

fn extractSlotAssign(node: template.NormalizedNode) ?[]const u8 {
    return switch (node) {
        .element => |element| blk: {
            for (element.directives) |directive| {
                switch (directive) {
                    .slot_assign => |slot_assign| break :blk slot_assign.slot_name,
                    else => {},
                }
            }
            break :blk null;
        },
        else => null,
    };
}

fn filterOutSlotAssign(
    directives: []const template.Directive,
    allocator: std.mem.Allocator,
) anyerror![]template.Directive {
    var out = std.ArrayList(template.Directive).empty;
    defer out.deinit(allocator);

    for (directives) |directive| {
        switch (directive) {
            .slot_assign => {},
            else => try out.append(allocator, directive),
        }
    }

    return try out.toOwnedSlice(allocator);
}

fn findSlotProvision(provisions: []const lir.SlotProvision, name: ?[]const u8) ?usize {
    for (provisions, 0..) |provision, idx| {
        if (sameOptionalString(provision.name, name)) return idx;
    }
    return null;
}

fn sameOptionalString(a: ?[]const u8, b: ?[]const u8) bool {
    if (a == null and b == null) return true;
    if (a == null or b == null) return false;
    return std.mem.eql(u8, a.?, b.?);
}

fn freeSlotProvisions(provisions: []lir.SlotProvision, allocator: std.mem.Allocator) void {
    for (provisions) |*provision| {
        for (provision.children) |*child| child.deinit(allocator);
        allocator.free(provision.children);
    }
    allocator.free(provisions);
}
