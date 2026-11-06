const std = @import("std");
const normalized = @import("../parser/template/normalized.zig");
const backend = @import("../../ffi/script_backend.zig");
const sir = @import("../sema/sir.zig");

pub const Range = struct { start: usize, end: usize };
pub const Record = struct { generated: Range, template: Range };

// Shared by metadata analysis and runtime lowering, so both resolve writes and
// captured callbacks against the real script bindings and lexical loop aliases.
pub fn bindingNames(script: *const sir.ScriptFacts, allocator: std.mem.Allocator) ![][]const u8 {
    var names = std.ArrayList([]const u8).empty;
    for (script.bindings) |binding| if (binding.template_visible) try names.append(allocator, binding.name);
    for (script.imports) |record| if (record.local_name.len > 0) try names.append(allocator, record.local_name);
    return names.toOwnedSlice(allocator);
}

pub fn append(out: *std.ArrayList(u8), source: []const u8, locals: []const []const u8, script_names: []const []const u8, argument: ?[]const u8, allocator: std.mem.Allocator) !Range {
    try out.appendSlice(allocator, "(__weiv_context");
    if (argument != null) try out.appendSlice(allocator, ",__weiv_argument");
    try out.appendSlice(allocator, ")=>{\n");
    if (argument) |name| {
        var shadowed = false;
        for (script_names) |binding| if (std.mem.eql(u8, binding, name)) {
            shadowed = true;
            break;
        };
        for (locals) |binding| if (std.mem.eql(u8, binding, name)) {
            shadowed = true;
            break;
        };
        if (!shadowed) try out.print(allocator, "const {s}=__weiv_argument;\n", .{name});
    }
    for (locals, 0..) |name, index| {
        if (std.mem.startsWith(u8, name, "__weiv_")) return error.CellReservedIdentifier;
        var shadowed = false;
        for (locals[index + 1 ..]) |inner| if (std.mem.eql(u8, name, inner)) {
            shadowed = true;
            break;
        };
        if (shadowed) continue;
        const key = try std.json.Stringify.valueAlloc(allocator, name, .{});
        defer allocator.free(key);
        try out.print(allocator, "const {s}=__weiv_context[{s}];\n", .{ name, key });
    }
    const handler_kind = if (argument != null) try backend.cellHandlerKind(source, allocator) else 0;
    try out.appendSlice(allocator, if (handler_kind == 2) "return ((__weiv_handler)=>typeof __weiv_handler===\"function\"?__weiv_handler(__weiv_argument):__weiv_handler)((" else "return (");
    const start = out.items.len;
    try out.appendSlice(allocator, source);
    const end = out.items.len;
    try out.appendSlice(allocator, ")");
    if (handler_kind == 1) try out.appendSlice(allocator, "?.(__weiv_argument)");
    if (handler_kind == 2) try out.appendSlice(allocator, ")");
    try out.appendSlice(allocator, ";\n}");
    return .{ .start = start, .end = end };
}

pub const Collector = struct {
    allocator: std.mem.Allocator,
    script: *std.ArrayList(u8),
    template: []const u8,
    script_names: []const []const u8,
    records: std.ArrayList(Record) = .empty,
    locals: std.ArrayList([]const u8) = .empty,
    include_pure: bool = false,

    fn expression(self: *Collector, source: []const u8, start: usize, argument: ?[]const u8) !void {
        // The emission planner reports unsupported syntax. Do not let it hide
        // otherwise valid script metadata during diagnostic inspection.
        backend.validateCellHandlerExpression(source, self.allocator) catch return;
        if (argument == null and !self.include_pure) {
            const probe = try std.fmt.allocPrint(self.allocator, "const __weiv_probe=()=>({s});", .{source});
            defer self.allocator.free(probe);
            const raw = try backend.analyzeModuleStateRaw(probe, "template.ts", self.allocator);
            defer self.allocator.free(raw);
            const parsed = try std.json.parseFromSlice(struct { ok: bool, bindings: []const struct { has_mutation: bool } }, self.allocator, raw, .{ .ignore_unknown_fields = true });
            defer parsed.deinit();
            if (!parsed.value.ok or parsed.value.bindings.len == 0 or !parsed.value.bindings[0].has_mutation) return;
        }
        if (self.records.items.len != 0) try self.script.append(self.allocator, ',');
        const range = try append(self.script, source, self.locals.items, self.script_names, argument, self.allocator);
        const found = std.mem.indexOfPos(u8, self.template, start, source) orelse start;
        try self.records.append(self.allocator, .{ .generated = range, .template = .{ .start = found, .end = found + source.len } });
    }

    pub fn walk(self: *Collector, nodes: []const normalized.Node) anyerror!void {
        for (nodes) |node| switch (node) {
            .text => {},
            .interpolation => |value| try self.expression(value.expression, value.span.start, null),
            .conditional => |value| {
                try self.expression(value.condition, value.span.start, null);
                try self.walk(value.consequent);
                try self.walk(value.alternate);
            },
            .for_loop => |value| {
                try self.expression(value.iterable_expr, value.span.start, null);
                try self.locals.append(self.allocator, value.item_name);
                defer _ = self.locals.pop();
                try self.walk(value.body);
            },
            .slot_outlet => |value| try self.walk(value.fallback_children),
            .element => |value| {
                for (value.directives) |directive| switch (directive) {
                    .bind => |binding| try self.expression(binding.expression, binding.span.start, null),
                    .event => |event| try self.expression(event.expression, event.span.start, if (value.tag_name.len > 0 and std.ascii.isUpper(value.tag_name[0])) "payload" else "event"),
                    else => {},
                };
                try self.walk(value.children);
            },
        };
    }
};
