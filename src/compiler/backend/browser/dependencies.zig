const std = @import("std");
const browser_render_tree = @import("render_tree/index.zig");
const component = @import("../../component_unit.zig");
const sir = @import("../../sema/sir.zig");
const tracked_roots = @import("tracked_roots.zig");

// Dependency analysis used by the browser runtime-region plan.
pub const DepList = struct {
    items: std.ArrayList([]const u8) = .empty,
    retain_imported_calls: bool = false,

    pub fn deinit(self: *DepList, allocator: std.mem.Allocator) void {
        self.items.deinit(allocator);
    }

    fn appendUnique(self: *DepList, allocator: std.mem.Allocator, name: []const u8) !void {
        for (self.items.items) |item| {
            if (std.mem.eql(u8, item, name)) return;
        }
        try self.items.append(allocator, name);
    }
};

pub fn collectNodeDeps(
    component_model: *const component.ComponentUnit,
    node: browser_render_tree.Node,
    loop_locals: []const []const u8,
    deps: *DepList,
    allocator: std.mem.Allocator,
) !void {
    switch (node) {
        .text => {},
        .interpolation => |interp| try collectExpressionDeps(component_model, interp.expression, loop_locals, deps, allocator),
        .element => |element| {
            for (element.bind_effects) |effect| {
                switch (effect) {
                    .bind => |bind_dir| try collectExpressionDeps(component_model, bind_dir.expression, loop_locals, deps, allocator),
                    .event => {},
                }
            }
            for (element.children) |child| {
                try collectNodeDeps(component_model, child, loop_locals, deps, allocator);
            }
        },
        .conditional => |conditional| {
            try collectExpressionDeps(component_model, conditional.condition, loop_locals, deps, allocator);
            for (conditional.consequent) |child| {
                try collectNodeDeps(component_model, child, loop_locals, deps, allocator);
            }
            for (conditional.alternate) |child| {
                try collectNodeDeps(component_model, child, loop_locals, deps, allocator);
            }
        },
        .for_loop => |for_loop| {
            try collectExpressionDeps(component_model, for_loop.iterable_expr, loop_locals, deps, allocator);
            var next_locals = std.ArrayList([]const u8).empty;
            defer next_locals.deinit(allocator);
            try next_locals.appendSlice(allocator, loop_locals);
            try next_locals.append(allocator, for_loop.item_name);
            for (for_loop.body) |child| {
                try collectNodeDeps(component_model, child, next_locals.items, deps, allocator);
            }
        },
        .component => |component_node| {
            for (component_node.bind_effects) |effect| {
                switch (effect) {
                    .bind => |bind_dir| try collectExpressionDeps(component_model, bind_dir.expression, loop_locals, deps, allocator),
                    .event => |event_dir| try collectExpressionDeps(component_model, event_dir.expression, loop_locals, deps, allocator),
                }
            }
            for (component_node.event_effects) |effect| {
                switch (effect) {
                    .bind => |bind_dir| try collectExpressionDeps(component_model, bind_dir.expression, loop_locals, deps, allocator),
                    .event => |event_dir| try collectExpressionDeps(component_model, event_dir.expression, loop_locals, deps, allocator),
                }
            }
            for (component_node.slot_provisions) |slot| {
                for (slot.children) |child| {
                    try collectNodeDeps(component_model, child, loop_locals, deps, allocator);
                }
            }
        },
        .slot_outlet => |slot_outlet| {
            for (slot_outlet.fallback_children) |child| {
                try collectNodeDeps(component_model, child, loop_locals, deps, allocator);
            }
        },
    }
}

pub fn collectExpressionDeps(
    component_model: *const component.ComponentUnit,
    expr: []const u8,
    loop_locals: []const []const u8,
    deps: *DepList,
    allocator: std.mem.Allocator,
) anyerror!void {
    try collectExpressionDepsWithTrail(component_model, expr, loop_locals, deps, allocator, &.{});
}

fn collectExpressionDepsWithTrail(
    component_model: *const component.ComponentUnit,
    expr: []const u8,
    loop_locals: []const []const u8,
    deps: *DepList,
    allocator: std.mem.Allocator,
    call_trail: []const []const u8,
) anyerror!void {
    if (component_model.lir_document.findExpression(expr)) |facts| {
        for (facts.references) |reference| {
            const ident = reference.name;
            if (reference.call and !deps.retain_imported_calls and tracked_roots.isImportedBinding(component_model, ident)) continue;
            if (reference.call) {
                if (findVisibleBinding(component_model, ident)) |binding| {
                    try deps.appendUnique(allocator, ident);
                    if (binding.callable and !containsName(call_trail, ident)) {
                        try collectCallableBindingDeps(component_model, binding, deps, allocator, call_trail);
                    }
                    continue;
                }
            }
            if (isVisibleBinding(component_model, ident) or containsName(loop_locals, ident)) {
                try deps.appendUnique(allocator, ident);
            }
        }
        return;
    }

    var i: usize = 0;
    while (i < expr.len) {
        const ch = expr[i];
        if (!isIdentStart(ch)) {
            i += 1;
            continue;
        }

        const start = i;
        i += 1;
        while (i < expr.len and isIdentContinue(expr[i])) i += 1;
        const ident = expr[start..i];
        const call = nextNonSpaceIs(expr, i, '(');

        if (isKeyword(ident)) continue;
        if (isPropertyAccessExpr(expr, start)) continue;
        if (call and !deps.retain_imported_calls and tracked_roots.isImportedBinding(component_model, ident)) continue;

        if (call) {
            if (findVisibleBinding(component_model, ident)) |binding| {
                try deps.appendUnique(allocator, ident);
                if (binding.callable and !containsName(call_trail, ident)) {
                    try collectCallableBindingDeps(component_model, binding, deps, allocator, call_trail);
                }
                continue;
            }
        }

        if (isVisibleBinding(component_model, ident) or containsName(loop_locals, ident)) {
            try deps.appendUnique(allocator, ident);
        }
    }
}

fn isVisibleBinding(component_model: *const component.ComponentUnit, name: []const u8) bool {
    return findVisibleBinding(component_model, name) != null;
}

fn findVisibleBinding(
    component_model: *const component.ComponentUnit,
    name: []const u8,
) ?sir.ScriptBinding {
    for (component_model.script.bindings) |binding| {
        if (binding.template_visible and std.mem.eql(u8, binding.name, name)) return binding;
    }
    return null;
}

pub fn retainVisibleBindingDeps(component_model: *const component.ComponentUnit, deps: *DepList) void {
    var write_index: usize = 0;
    for (deps.items.items) |dep| {
        if (!isVisibleBinding(component_model, dep)) continue;
        deps.items.items[write_index] = dep;
        write_index += 1;
    }
    deps.items.items.len = write_index;
}

fn nextNonSpaceIs(expr: []const u8, start: usize, needle: u8) bool {
    var cursor = start;
    while (cursor < expr.len and isWhitespace(expr[cursor])) cursor += 1;
    return cursor < expr.len and expr[cursor] == needle;
}

fn isPropertyAccessExpr(expr: []const u8, ident_start: usize) bool {
    var cursor = ident_start;
    while (cursor > 0) {
        cursor -= 1;
        if (isWhitespace(expr[cursor])) continue;
        return expr[cursor] == '.' and !(cursor >= 2 and std.mem.eql(u8, expr[cursor - 2 .. cursor + 1], "..."));
    }
    return false;
}

fn isKeyword(ident: []const u8) bool {
    const keywords = [_][]const u8{
        "true",
        "false",
        "null",
        "undefined",
        "typeof",
        "instanceof",
        "return",
        "new",
        "await",
    };
    for (keywords) |keyword| {
        if (std.mem.eql(u8, ident, keyword)) return true;
    }
    return false;
}

fn isIdentStart(ch: u8) bool {
    return std.ascii.isAlphabetic(ch) or ch == '_' or ch == '$';
}

fn isIdentContinue(ch: u8) bool {
    return isIdentStart(ch) or std.ascii.isDigit(ch);
}

fn isWhitespace(ch: u8) bool {
    return ch == ' ' or ch == '\n' or ch == '\r' or ch == '\t';
}

fn collectCallableBindingDeps(
    component_model: *const component.ComponentUnit,
    binding: sir.ScriptBinding,
    deps: *DepList,
    allocator: std.mem.Allocator,
    call_trail: []const []const u8,
) anyerror!void {
    const helper = findHelperFacts(component_model, binding.name) orelse return;

    var next_trail = std.ArrayList([]const u8).empty;
    defer next_trail.deinit(allocator);
    try next_trail.appendSlice(allocator, call_trail);
    try next_trail.append(allocator, binding.name);

    for (helper.reads) |name| {
        try deps.appendUnique(allocator, name);
    }

    for (helper.calls) |name| {
        try deps.appendUnique(allocator, name);
        if (containsName(next_trail.items, name)) continue;
        if (findVisibleBinding(component_model, name)) |next_binding| {
            if (next_binding.callable) {
                try collectCallableBindingDeps(component_model, next_binding, deps, allocator, next_trail.items);
            }
        }
    }
}

fn findHelperFacts(
    component_model: *const component.ComponentUnit,
    name: []const u8,
) ?sir.HelperFacts {
    for (component_model.script.state_facts.helpers) |helper| {
        if (std.mem.eql(u8, helper.name, name)) return helper;
    }
    return null;
}

fn containsName(names: []const []const u8, needle: []const u8) bool {
    for (names) |name| {
        if (std.mem.eql(u8, name, needle)) return true;
    }
    return false;
}
