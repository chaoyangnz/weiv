const std = @import("std");
const component = @import("../component_unit.zig");
const diagnostics = @import("../diagnostics.zig");
const normalized = @import("../parser/template/normalized.zig");
const functions = @import("template_functions.zig");
const backend = @import("../../ffi/script_backend.zig");

// Only used after emission fails. Probe each expression against the real script
// and selected roots, so errors retain lexical scope without adding success-path
// compiler work or blaming a template for a script declaration failure.
pub fn inspect(unit: *const component.ComponentUnit, names: []const u8, bag: *diagnostics.DiagnosticBag, allocator: std.mem.Allocator) !void {
    const baseline = backend.lowerCellsWithExpressions(unit.sfc_document.script.content, unit.source_path, names, "", allocator) catch |err| {
        if (err == error.OutOfMemory) return err;
        _ = try inspectScript(.{ .text = unit.sfc_document.script.content, .path = unit.source_path, .document = unit.source, .offset = unit.sfc_document.script.content_span.start }, names, false, bag, allocator);
        return;
    };
    allocator.free(baseline);
    var probe = Probe{ .unit = unit, .names = names, .bag = bag, .allocator = allocator, .script_names = try functions.bindingNames(&unit.script, allocator) };
    defer allocator.free(probe.script_names);
    defer probe.locals.deinit(allocator);
    try probe.walk(unit.normalized_template.nodes);
}

pub const ScriptSource = struct { text: []const u8, path: []const u8, document: []const u8, offset: usize = 0 };

pub fn inspectScript(source: ScriptSource, names: []const u8, module: bool, bag: *diagnostics.DiagnosticBag, allocator: std.mem.Allocator) !bool {
    const raw = try backend.cellScriptDiagnosticsRaw(source.text, source.path, names, module, allocator);
    defer allocator.free(raw);
    const parsed = try std.json.parseFromSlice([]const struct { reason: []const u8, span_start: usize, span_end: usize, message: ?[]const u8 = null }, allocator, raw, .{});
    defer parsed.deinit();
    var reported = false;
    for (parsed.value) |entry| {
        if (entry.span_start > entry.span_end or entry.span_end > source.text.len) continue;
        const span = diagnostics.Span{ .start = source.offset + entry.span_start, .end = source.offset + entry.span_end };
        if (entry.message) |message| {
            const guidance = try std.fmt.allocPrint(allocator, "{s}. Correct this script/module syntax before reactive lowering.", .{message});
            defer allocator.free(guidance);
            try bag.appendOwned(allocator, "script.syntax", .@"error", guidance, .emit, source.path, span, diagnostics.computeLocation(source.document, span), true);
        } else try appendFailure(bag, source.document, source.path, span, backend.cellLoweringError(entry.reason), allocator);
        reported = true;
    }
    return reported;
}

fn appendFailure(bag: *diagnostics.DiagnosticBag, document: []const u8, path: []const u8, span: diagnostics.Span, failure: anyerror, allocator: std.mem.Allocator) !void {
    const detail: struct { []const u8, []const u8 } = switch (failure) {
        error.CellTemplateMutationUnsupported => .{ "reactivity.render_mutation", "Render expressions cannot mutate state immediately. Move this write into an event handler or deferred callback." },
        error.CellConstAssignmentUnsupported => .{ "reactivity.readonly_assignment", "This expression writes a readonly binding. Use let for replaceable local state, a managed module's exported mutation function for imports, or update an item's supported data members instead of replacing a loop alias." },
        error.CellTemplateUntrackedAssignmentUnsupported => .{ "reactivity.untracked_assignment", "This expression replaces a binding that is not managed reactive state. Use a let binding for replaceable callable state; update props through their owner." },
        error.CellDynamicEvalUnsupported => .{ "reactivity.dynamic_eval", "Dynamic eval cannot preserve compiler-managed reactive bindings. Use a statically defined function or an explicit subscription adapter." },
        error.CellReservedIdentifier => .{ "reactivity.reserved_identifier", "Names beginning with __weiv_ are reserved for compiler internals. Rename this binding." },
        error.CellVarDeclarationUnsupported => .{ "reactivity.unsupported_declaration", "Compiler-managed state requires let or const declarations. Replace this var declaration with a lexical declaration and check its initialization order." },
        error.CellTopLevelAwaitUnsupported => .{ "reactivity.unsupported_await", "Synchronous state setup and binding-pattern extraction cannot await here. Move asynchronous work into an async helper; managed modules may await their pattern's input before extraction." },
        error.CellAmbientDeclarationUnsupported => .{ "reactivity.ambient_declaration", "An ambient declaration has no runtime storage for managed state. Provide a real initializer or import state with an explicit observable or subscription contract." },
        error.CellComponentDefaultExportUnsupported => .{ "reactivity.component_default_export", "Component setup cannot contain a default export. Remove this export and use the component's template and props interface; shared modules may retain native default exports." },
        else => .{ "reactivity.unsupported_expression", "This expression cannot be lowered with reactive state. Simplify it into a statically defined script helper or use an explicit subscription adapter." },
    };
    const message = try std.fmt.allocPrint(allocator, "{s} ({s})", .{ detail[1], @errorName(failure) });
    defer allocator.free(message);
    try bag.appendOwned(allocator, detail[0], .@"error", message, .emit, path, span, diagnostics.computeLocation(document, span), true);
}

const Probe = struct {
    unit: *const component.ComponentUnit,
    names: []const u8,
    bag: *diagnostics.DiagnosticBag,
    allocator: std.mem.Allocator,
    script_names: []const []const u8,
    locals: std.ArrayList([]const u8) = .empty,

    fn expression(self: *Probe, source: []const u8, enclosing: diagnostics.Span, argument: ?[]const u8) !void {
        const failure: anyerror = blk: {
            var evaluator = std.ArrayList(u8).empty;
            defer evaluator.deinit(self.allocator);
            _ = functions.append(&evaluator, source, self.locals.items, self.script_names, argument, self.allocator) catch |err| break :blk err;
            const lowered = backend.lowerCellsWithExpressions(self.unit.sfc_document.script.content, self.unit.source_path, self.names, evaluator.items, self.allocator) catch |err| break :blk err;
            self.allocator.free(lowered);
            if (argument == null) backend.validateCellExpression(source, self.allocator) catch |err| break :blk err else backend.validateCellHandlerExpression(source, self.allocator) catch |err| break :blk err;
            return;
        };
        if (failure == error.OutOfMemory) return failure;
        const template = self.unit.sfc_document.template.content;
        const base = self.unit.sfc_document.template.content_span.start;
        const pointer = @intFromPtr(source.ptr);
        const template_pointer = @intFromPtr(template.ptr);
        const relative: diagnostics.Span = if (pointer >= template_pointer and pointer + source.len <= template_pointer + template.len)
            .{ .start = pointer - template_pointer, .end = pointer - template_pointer + source.len }
        else if (std.mem.indexOf(u8, template[@min(enclosing.start, template.len)..@min(enclosing.end, template.len)], source)) |found|
            .{ .start = enclosing.start + found, .end = enclosing.start + found + source.len }
        else
            enclosing;
        const span = diagnostics.Span{ .start = base + relative.start, .end = base + relative.end };
        try appendFailure(self.bag, self.unit.source, self.unit.source_path, span, failure, self.allocator);
    }

    fn walk(self: *Probe, nodes: []const normalized.Node) anyerror!void {
        for (nodes) |node| switch (node) {
            .text => {},
            .interpolation => |value| try self.expression(value.expression, .{ .start = value.span.start, .end = value.span.end }, null),
            .conditional => |value| {
                try self.expression(value.condition, .{ .start = value.span.start, .end = value.span.end }, null);
                try self.walk(value.consequent);
                try self.walk(value.alternate);
            },
            .for_loop => |value| {
                try self.expression(value.iterable_expr, .{ .start = value.span.start, .end = value.span.end }, null);
                try self.locals.append(self.allocator, value.item_name);
                defer _ = self.locals.pop();
                try self.walk(value.body);
            },
            .slot_outlet => |value| try self.walk(value.fallback_children),
            .element => |value| {
                for (value.directives) |directive| switch (directive) {
                    .bind => |binding| try self.expression(binding.expression, .{ .start = binding.span.start, .end = binding.span.end }, null),
                    .event => |event| try self.expression(event.expression, .{ .start = event.span.start, .end = event.span.end }, if (value.tag_name.len > 0 and std.ascii.isUpper(value.tag_name[0])) "payload" else "event"),
                    else => {},
                };
                try self.walk(value.children);
            },
        };
    }
};
