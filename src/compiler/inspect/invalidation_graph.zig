const std = @import("std");
const browser_render_tree = @import("../backend/browser/render_tree/index.zig");
const component_unit = @import("../component_unit.zig");
const sir = @import("../sema/sir.zig");
const tracked_roots = @import("../backend/browser/tracked_roots.zig");
const tracked_paths = @import("../backend/browser/tracked_paths.zig");
const region_graph = @import("../backend/browser/region_graph.zig");
const dependencies = @import("../backend/browser/dependencies.zig");

const DepList = dependencies.DepList;

const BoundaryKind = enum {
    template_event,
    child_event,
    slot_update,
};

const DiagnosticKind = enum {
    hidden_state,
    runtime_evaluate_fallback,
};

const DiagnosticSeverity = enum {
    warning,
    info,
};

const Diagnostic = struct {
    severity: DiagnosticSeverity,
    kind: DiagnosticKind,
    subject: []const u8,
    related: ?[]const u8 = null,
    offset: ?usize = null,
    reason: ?[]const u8 = null,
};

const Formatter = struct {
    component: *const component_unit.ComponentUnit,
    out: *std.ArrayList(u8),
    allocator: std.mem.Allocator,
    next_region_id: usize = 1,
    diagnostics: std.ArrayList(Diagnostic) = .empty,
    tracked_table: *tracked_paths.Table,
    runtime_graph: *const region_graph.Graph,

    fn deinit(self: *Formatter) void {
        self.diagnostics.deinit(self.allocator);
    }

    fn format(self: *Formatter, render_tree: *const browser_render_tree.Document) !void {
        try self.out.print(self.allocator, "invalidation-graph source={s}\n", .{self.component.source_path});
        try self.out.appendSlice(self.allocator, "regions\n");
        try self.formatNodes(render_tree.nodes, 1, &.{});
        try self.out.appendSlice(self.allocator, "runtime-regions\n");
        try self.formatRuntimeRegions();
        if (self.tracked_table.roots.items.len > 0) {
            try self.out.appendSlice(self.allocator, "tracked-roots\n");
            try self.formatTrackedRoots();
            try self.out.appendSlice(self.allocator, "tracked-paths\n");
            try self.formatTrackedPaths();
        }
        try self.out.appendSlice(self.allocator, "mutations\n");
        try self.formatMutations();
        try self.out.appendSlice(self.allocator, "callback-registrations\n");
        try self.formatCallbackRegistrations();
        try self.out.appendSlice(self.allocator, "boundaries\n");
        try self.formatBoundaries(render_tree.nodes, 1);
        if (self.diagnostics.items.len > 0) {
            try self.out.appendSlice(self.allocator, "diagnostics\n");
            for (self.diagnostics.items) |diagnostic| {
                try self.writeIndent(1);
                switch (diagnostic.kind) {
                    .hidden_state => try self.out.print(
                        self.allocator,
                        "{s} hidden-state expression={s} reason={s}\n",
                        .{ severityLabel(diagnostic.severity), diagnostic.subject, diagnostic.reason orelse "no-visible-component-dependency" },
                    ),
                    .runtime_evaluate_fallback => try self.out.print(
                        self.allocator,
                        "{s} runtime-evaluate-fallback expression={s} reason={s}\n",
                        .{ severityLabel(diagnostic.severity), diagnostic.subject, classifyEvaluateFallback(diagnostic.subject) },
                    ),
                }
            }
        }
    }

    fn formatNodes(self: *Formatter, nodes: []const browser_render_tree.Node, indent: usize, loop_locals: []const []const u8) !void {
        for (nodes) |node| {
            switch (node) {
                .text => {},
                .interpolation => |interp| {
                    try self.writeRegion(indent, "text", interp.ref_id, interp.expression, loop_locals);
                },
                .element => |element| {
                    for (element.bind_effects) |effect| {
                        switch (effect) {
                            .bind => |bind| try self.writeRegionWithName(indent, "attribute", element.ref_id, bind.target_name, bind.expression, loop_locals),
                            .event => {},
                        }
                    }
                    try self.formatNodes(element.children, indent, loop_locals);
                },
                .conditional => |conditional| {
                    try self.writeRegion(indent, "conditional", conditional.state_ref_id, conditional.condition, loop_locals);
                    try self.formatNodes(conditional.consequent, indent + 1, loop_locals);
                    try self.formatNodes(conditional.alternate, indent + 1, loop_locals);
                },
                .for_loop => |for_loop| {
                    try self.writeRegionWithName(indent, "loop", for_loop.state_ref_id, for_loop.item_name, for_loop.iterable_expr, loop_locals);

                    var next_locals = std.ArrayList([]const u8).empty;
                    defer next_locals.deinit(self.allocator);
                    try next_locals.appendSlice(self.allocator, loop_locals);
                    try next_locals.append(self.allocator, for_loop.item_name);
                    try self.formatNodes(for_loop.body, indent + 1, next_locals.items);
                },
                .component => |component_node| {
                    var deps = DepList{};
                    defer deps.deinit(self.allocator);
                    for (component_node.bind_effects) |effect| {
                        switch (effect) {
                            .bind => |bind| try self.collectExpressionDeps(bind.expression, loop_locals, &deps),
                            .event => {},
                        }
                    }
                    try self.writeRegionLine(indent, "child", component_node.handle_ref_id, component_node.tag_name, null, deps.items.items, &.{});
                    for (component_node.slot_provisions) |slot| {
                        const slot_name = slot.name orelse "default";
                        try self.writeRegionLine(indent + 1, "slot", component_node.handle_ref_id, slot_name, null, &.{}, &.{});
                        try self.formatNodes(slot.children, indent + 2, loop_locals);
                    }
                },
                .slot_outlet => |slot_outlet| {
                    const slot_name = slot_outlet.name orelse "default";
                    try self.writeRegionLine(indent, "slot", slot_outlet.handle_ref_id, slot_name, null, &.{}, &.{});
                    try self.formatNodes(slot_outlet.fallback_children, indent + 1, loop_locals);
                },
            }
        }
    }

    fn formatBoundaries(self: *Formatter, nodes: []const browser_render_tree.Node, indent: usize) !void {
        for (nodes) |node| {
            switch (node) {
                .element => |element| {
                    for (element.event_effects) |effect| {
                        switch (effect) {
                            .event => |event| try self.writeBoundary(indent, .template_event, event.event_name, event.expression),
                            .bind => {},
                        }
                    }
                    try self.formatBoundaries(element.children, indent);
                },
                .conditional => |conditional| {
                    try self.formatBoundaries(conditional.consequent, indent);
                    try self.formatBoundaries(conditional.alternate, indent);
                },
                .for_loop => |for_loop| try self.formatBoundaries(for_loop.body, indent),
                .component => |component_node| {
                    for (component_node.event_effects) |effect| {
                        switch (effect) {
                            .event => |event| try self.writeBoundary(indent, .child_event, event.event_name, event.expression),
                            .bind => {},
                        }
                    }
                    for (component_node.slot_provisions) |slot| {
                        try self.writeBoundary(indent, .slot_update, slot.name orelse "default", "compiler-emitted");
                        try self.formatBoundaries(slot.children, indent + 1);
                    }
                },
                .slot_outlet => |slot_outlet| try self.formatBoundaries(slot_outlet.fallback_children, indent),
                .text, .interpolation => {},
            }
        }
    }

    fn formatMutations(self: *Formatter) !void {
        for (self.component.script.state_facts.mutations) |mutation| {
            const absolute_offset = self.component.sfc_document.script.content_span.start + mutation.span_start;

            try self.writeIndent(1);
            try self.out.print(self.allocator, "{s} {s} offset={d}\n", .{
                mutation.binding,
                mutation.kind,
                absolute_offset,
            });
        }
    }

    fn formatCallbackRegistrations(self: *Formatter) !void {
        for (self.component.script.state_facts.callback_registrations) |registration| {
            try self.writeIndent(1);
            try self.out.print(
                self.allocator,
                "callback callee={s} kind={s} owned_candidate={s} reason={s} offset={d}\n",
                .{
                    registration.callee,
                    registration.callback_kind,
                    if (registration.owned_candidate) "true" else "false",
                    registration.reason,
                    self.component.sfc_document.script.content_span.start + registration.callback_span_start,
                },
            );
        }
    }

    fn formatTrackedRoots(self: *Formatter) !void {
        for (self.tracked_table.roots.items) |root| {
            try self.writeIndent(1);
            try self.out.print(self.allocator, "root id={d} binding={s} kind={s}\n", .{
                root.id,
                root.binding_name,
                root.kind,
            });
        }
    }

    fn formatRuntimeRegions(self: *Formatter) !void {
        for (self.runtime_graph.regions.items) |region| {
            try self.writeIndent(1);
            try self.out.print(self.allocator, "#{d} {s} ref={d}", .{ region.id, region.kind, region.ref_id });
            if (region.name) |name| try self.out.print(self.allocator, " name={s}", .{name});
            try self.out.appendSlice(self.allocator, " deps=[");
            for (region.dependency_names.items, 0..) |dep, idx| {
                if (idx > 0) try self.out.appendSlice(self.allocator, ",");
                try self.out.appendSlice(self.allocator, dep);
            }
            try self.out.appendSlice(self.allocator, "] tracked_paths=[");
            for (region.tracked_path_ids.items, 0..) |id, idx| {
                if (idx > 0) try self.out.appendSlice(self.allocator, ",");
                try self.out.print(self.allocator, "{d}", .{id});
            }
            try self.out.appendSlice(self.allocator, "]\n");
        }
    }

    fn formatTrackedPaths(self: *Formatter) !void {
        for (self.tracked_table.paths.items) |path| {
            try self.writeIndent(1);
            try self.out.print(self.allocator, "path id={d} root={d} path={s}", .{
                path.id,
                path.root_id,
                path.path,
            });
            if (path.parent_path_id) |parent_id| {
                try self.out.print(self.allocator, " parent={d}", .{parent_id});
            }
            try self.out.appendSlice(self.allocator, "\n");
        }
    }

    fn writeRegion(self: *Formatter, indent: usize, kind: []const u8, ref_id: usize, expr: []const u8, loop_locals: []const []const u8) !void {
        var deps = DepList{};
        defer deps.deinit(self.allocator);
        try self.collectExpressionDeps(expr, loop_locals, &deps);
        var tracked_path_ids = std.ArrayList(usize).empty;
        defer tracked_path_ids.deinit(self.allocator);
        try self.tracked_table.collectExpressionIds(expr, &tracked_path_ids);
        try self.writeRegionLine(indent, kind, ref_id, null, expr, deps.items.items, tracked_path_ids.items);
    }

    fn writeRegionWithName(
        self: *Formatter,
        indent: usize,
        kind: []const u8,
        ref_id: usize,
        name: []const u8,
        expr: []const u8,
        loop_locals: []const []const u8,
    ) !void {
        var deps = DepList{};
        defer deps.deinit(self.allocator);
        try self.collectExpressionDeps(expr, loop_locals, &deps);
        var tracked_path_ids = std.ArrayList(usize).empty;
        defer tracked_path_ids.deinit(self.allocator);
        try self.tracked_table.collectExpressionIds(expr, &tracked_path_ids);
        try self.writeRegionLine(indent, kind, ref_id, name, expr, deps.items.items, tracked_path_ids.items);
    }

    fn writeRegionLine(
        self: *Formatter,
        indent: usize,
        kind: []const u8,
        ref_id: usize,
        name: ?[]const u8,
        expr: ?[]const u8,
        deps: []const []const u8,
        tracked_path_ids: []const usize,
    ) !void {
        const id = self.next_region_id;
        self.next_region_id += 1;

        try self.writeIndent(indent);
        try self.out.print(self.allocator, "#{d} {s} ref={d}", .{ id, kind, ref_id });
        if (name) |value| try self.out.print(self.allocator, " name={s}", .{value});
        if (expr) |value| {
            try self.out.print(self.allocator, " expr={s}", .{value});
            const compiled_direct = expressionCompilesDirect(value);
            try self.out.print(self.allocator, " eval={s}", .{
                if (compiled_direct) "direct" else "fallback",
            });
            if (!compiled_direct) {
                try self.out.print(self.allocator, " reason={s}", .{classifyEvaluateFallback(value)});
                try self.diagnostics.append(self.allocator, .{
                    .severity = .info,
                    .kind = .runtime_evaluate_fallback,
                    .subject = value,
                });
            }
        }
        try self.out.appendSlice(self.allocator, " deps=[");
        for (deps, 0..) |dep, idx| {
            if (idx > 0) try self.out.appendSlice(self.allocator, ",");
            try self.out.appendSlice(self.allocator, dep);
        }
        try self.out.appendSlice(self.allocator, "]");
        if (tracked_path_ids.len > 0) {
            try self.out.appendSlice(self.allocator, " tracked_paths=[");
            for (tracked_path_ids, 0..) |path_id, idx| {
                if (idx > 0) try self.out.appendSlice(self.allocator, ",");
                try self.out.print(self.allocator, "{d}", .{path_id});
            }
            try self.out.appendSlice(self.allocator, "]");
        }
        try self.out.appendSlice(self.allocator, "\n");
    }

    fn writeBoundary(self: *Formatter, indent: usize, kind: BoundaryKind, name: []const u8, expr: []const u8) !void {
        try self.writeIndent(indent);
        try self.out.print(self.allocator, "{s} name={s} expr={s} owned=true", .{
            switch (kind) {
                .template_event => "template-event",
                .child_event => "child-event",
                .slot_update => "slot-update",
            },
            name,
            expr,
        });
        if (kind == .template_event and self.isAsyncFunction(expr)) {
            try self.out.appendSlice(self.allocator, " async=true");
        }
        try self.out.appendSlice(self.allocator, "\n");
    }

    fn collectExpressionDeps(self: *Formatter, expr: []const u8, loop_locals: []const []const u8, deps: *DepList) anyerror!void {
        try dependencies.collectExpressionDeps(self.component, expr, loop_locals, deps, self.allocator);
        var saw_call = false;
        var i: usize = 0;
        while (i < expr.len) {
            if (!isIdentStart(expr[i])) {
                i += 1;
                continue;
            }
            const start = i;
            i += 1;
            while (i < expr.len and isIdentContinue(expr[i])) i += 1;
            const ident = expr[start..i];
            if (!nextNonSpaceIs(expr, i, '(')) continue;
            saw_call = true;
            if (isKeyword(ident) or isPropertyAccess(expr, start) or tracked_roots.isImportedBinding(self.component, ident)) continue;
            const binding = self.findVisibleBinding(ident) orelse continue;
            if (!binding.callable) continue;
            const helper = self.findHelperFacts(binding.name) orelse continue;
            if (helper.contains_external_reads) {
                try self.diagnostics.append(self.allocator, .{
                    .severity = .warning,
                    .kind = .hidden_state,
                    .subject = expr,
                    .reason = "helper-contains-external-reads",
                });
            } else if (helper.contains_side_effects) {
                try self.diagnostics.append(self.allocator, .{
                    .severity = .warning,
                    .kind = .hidden_state,
                    .subject = expr,
                    .reason = "helper-contains-side-effects",
                });
            }
        }
        if (deps.items.items.len == 0 and saw_call) {
            try self.diagnostics.append(self.allocator, .{
                .severity = .warning,
                .kind = .hidden_state,
                .subject = expr,
                .reason = "no-visible-component-dependency",
            });
        }
    }

    fn findVisibleBinding(self: *const Formatter, name: []const u8) ?sir.ScriptBinding {
        for (self.component.script.bindings) |binding| {
            if (binding.template_visible and std.mem.eql(u8, binding.name, name)) return binding;
        }
        return null;
    }

    fn findHelperFacts(self: *const Formatter, name: []const u8) ?sir.HelperFacts {
        for (self.component.script.state_facts.helpers) |helper| {
            if (std.mem.eql(u8, helper.name, name)) return helper;
        }
        return null;
    }

    fn isAsyncFunction(self: *const Formatter, name: []const u8) bool {
        const script = self.component.sfc_document.script.content;
        const pattern = std.fmt.allocPrint(self.allocator, "async function {s}", .{name}) catch return false;
        defer self.allocator.free(pattern);
        return std.mem.indexOf(u8, script, pattern) != null;
    }

    fn writeIndent(self: *Formatter, indent: usize) !void {
        for (0..indent) |_| try self.out.appendSlice(self.allocator, "  ");
    }
};

pub fn formatDocument(
    component: *const component_unit.ComponentUnit,
    render_tree: *const browser_render_tree.Document,
    allocator: std.mem.Allocator,
) ![]u8 {
    var out = std.ArrayList(u8).empty;
    defer out.deinit(allocator);

    var runtime_graph = try region_graph.build(component, render_tree, allocator);
    defer runtime_graph.deinit();

    var formatter = Formatter{
        .component = component,
        .out = &out,
        .allocator = allocator,
        .tracked_table = &runtime_graph.table,
        .runtime_graph = &runtime_graph,
    };
    defer formatter.deinit();

    try formatter.format(render_tree);
    return try out.toOwnedSlice(allocator);
}

fn containsName(names: []const []const u8, needle: []const u8) bool {
    for (names) |name| {
        if (std.mem.eql(u8, name, needle)) return true;
    }
    return false;
}

fn isPropertyAccess(expr: []const u8, ident_start: usize) bool {
    if (ident_start == 0) return false;
    var idx = ident_start;
    while (idx > 0) {
        idx -= 1;
        if (isWhitespace(expr[idx])) continue;
        return expr[idx] == '.' and !(idx >= 2 and std.mem.eql(u8, expr[idx - 2 .. idx + 1], "..."));
    }
    return false;
}

fn nextNonSpaceIs(expr: []const u8, idx: usize, expected: u8) bool {
    var cursor = idx;
    while (cursor < expr.len) : (cursor += 1) {
        if (isWhitespace(expr[cursor])) continue;
        return expr[cursor] == expected;
    }
    return false;
}

fn isKeyword(value: []const u8) bool {
    const keywords = [_][]const u8{
        "true",
        "false",
        "null",
        "undefined",
        "if",
        "else",
        "return",
        "typeof",
        "instanceof",
        "new",
        "await",
        "async",
        "event",
    };
    for (keywords) |keyword| {
        if (std.mem.eql(u8, value, keyword)) return true;
    }
    return false;
}

fn isIdentStart(ch: u8) bool {
    return (ch >= 'a' and ch <= 'z') or
        (ch >= 'A' and ch <= 'Z') or
        ch == '_' or
        ch == '$';
}

fn isIdentContinue(ch: u8) bool {
    return isIdentStart(ch) or (ch >= '0' and ch <= '9');
}

fn consumeIdentifierSlice(source: []const u8, cursor: *usize) bool {
    if (cursor.* >= source.len or !isIdentStart(source[cursor.*])) return false;
    cursor.* += 1;
    while (cursor.* < source.len and isIdentContinue(source[cursor.*])) cursor.* += 1;
    return true;
}

fn isWhitespace(ch: u8) bool {
    return ch == ' ' or ch == '\n' or ch == '\r' or ch == '\t';
}

fn expressionCompilesDirect(expression: []const u8) bool {
    const trimmed = std.mem.trim(u8, expression, &std.ascii.whitespace);
    if (trimmed.len == 0) return true;
    if (isLiteralExpression(trimmed)) return true;
    if (isSimpleAccessExpression(trimmed)) return true;
    if (canRewriteScopedCallExpression(trimmed)) return true;
    return canRewriteScopedExpression(trimmed);
}

fn classifyEvaluateFallback(expression: []const u8) []const u8 {
    const trimmed = std.mem.trim(u8, expression, &std.ascii.whitespace);
    if (std.mem.indexOf(u8, trimmed, "=>") != null) return "callback-argument";
    if (std.mem.indexOfScalar(u8, trimmed, '(') != null) return "dynamic-call-arguments";
    return "complex-expression";
}

fn severityLabel(severity: DiagnosticSeverity) []const u8 {
    return switch (severity) {
        .warning => "warning",
        .info => "info",
    };
}

fn canRewriteScopedCallExpression(expression: []const u8) bool {
    const open_paren = std.mem.indexOfScalar(u8, expression, '(') orelse return false;
    const callee = std.mem.trimEnd(u8, expression[0..open_paren], &std.ascii.whitespace);
    if (callee.len == 0 or !isSimpleAccessExpression(callee)) return false;

    const close_paren = findMatchingParenForward(expression, open_paren) orelse return false;
    const suffix = std.mem.trim(u8, expression[close_paren + 1 ..], &std.ascii.whitespace);
    if (suffix.len != 0 and !isSimpleCallSuffixExpression(suffix)) return false;

    var args = std.ArrayList([]const u8).empty;
    defer args.deinit(std.heap.page_allocator);
    splitCallArguments(expression[open_paren + 1 .. close_paren], &args) catch return false;
    for (args.items) |arg| {
        const trimmed_arg = std.mem.trim(u8, arg, &std.ascii.whitespace);
        if (trimmed_arg.len == 0) continue;
        if (canRewriteArrowCallbackExpression(trimmed_arg)) continue;
        if (!canRewriteScopedExpression(trimmed_arg)) return false;
    }
    return true;
}

fn canRewriteScopedExpression(expression: []const u8) bool {
    return canRewriteScopedExpressionWithLocals(expression, &.{});
}

fn canRewriteScopedExpressionWithLocals(expression: []const u8, locals: []const []const u8) bool {
    var cursor: usize = 0;
    while (cursor < expression.len) {
        const ch = expression[cursor];
        if (isWhitespace(ch)) {
            cursor += 1;
            continue;
        }
        if (ch == '\'' or ch == '"') {
            cursor = scanQuotedString(expression, cursor) orelse return false;
            cursor += 1;
            continue;
        }
        if (isIdentStart(ch)) {
            const start = cursor;
            cursor += 1;
            while (cursor < expression.len and isIdentContinue(expression[cursor])) cursor += 1;
            const ident = expression[start..cursor];
            if (nextNonSpaceIs(expression, cursor, '(')) return false;
            if (isKeyword(ident) or containsName(locals, ident) or isPropertyAccess(expression, start)) continue;
            continue;
        }
        if (std.ascii.isDigit(ch)) {
            cursor += 1;
            while (cursor < expression.len and (std.ascii.isDigit(expression[cursor]) or expression[cursor] == '.')) cursor += 1;
            continue;
        }
        if (isSupportedExpressionPunctuation(ch)) {
            cursor += 1;
            continue;
        }
        return false;
    }
    return true;
}

fn canRewriteArrowCallbackExpression(expression: []const u8) bool {
    const arrow = std.mem.indexOf(u8, expression, "=>") orelse return false;
    const params_expr = std.mem.trim(u8, expression[0..arrow], &std.ascii.whitespace);
    const raw_body_expr = std.mem.trim(u8, expression[arrow + 2 ..], &std.ascii.whitespace);
    const body_expr = extractArrowCallbackReturnExpression(raw_body_expr) orelse return false;
    if (params_expr.len == 0 or body_expr.len == 0) return false;

    const param = parseArrowCallbackParam(params_expr) orelse return false;
    const locals = [_][]const u8{param};
    return canRewriteScopedExpressionWithLocals(body_expr, &locals);
}

fn parseArrowCallbackParam(params_expr: []const u8) ?[]const u8 {
    const trimmed = std.mem.trim(u8, params_expr, &std.ascii.whitespace);
    if (trimmed.len == 0) return null;
    if (trimmed[0] == '(') {
        if (trimmed[trimmed.len - 1] != ')') return null;
        const inner = std.mem.trim(u8, trimmed[1 .. trimmed.len - 1], &std.ascii.whitespace);
        if (inner.len == 0 or !isSimpleAccessExpression(inner)) return null;
        return inner;
    }
    if (!isSimpleAccessExpression(trimmed)) return null;
    return trimmed;
}

fn extractArrowCallbackReturnExpression(body_expr: []const u8) ?[]const u8 {
    const trimmed = std.mem.trim(u8, body_expr, &std.ascii.whitespace);
    if (trimmed.len == 0) return null;
    if (trimmed[0] != '{') return trimmed;
    if (trimmed[trimmed.len - 1] != '}') return null;

    const inner = std.mem.trim(u8, trimmed[1 .. trimmed.len - 1], &std.ascii.whitespace);
    if (!std.mem.startsWith(u8, inner, "return")) return null;

    const return_expr = std.mem.trim(u8, inner["return".len..], &std.ascii.whitespace);
    if (return_expr.len == 0) return null;
    if (return_expr[return_expr.len - 1] != ';') return null;

    const expr = std.mem.trim(u8, return_expr[0 .. return_expr.len - 1], &std.ascii.whitespace);
    if (expr.len == 0) return null;
    return expr;
}

fn isSimpleCallSuffixExpression(expression: []const u8) bool {
    var cursor: usize = 0;
    while (cursor < expression.len) {
        if (expression[cursor] != '.') return false;
        cursor += 1;
        if (!consumeIdentifier(expression, &cursor)) return false;
    }
    return true;
}

fn isLiteralExpression(expression: []const u8) bool {
    if (expression.len == 0) return false;
    if ((expression[0] == '\'' and expression[expression.len - 1] == '\'') or
        (expression[0] == '"' and expression[expression.len - 1] == '"')) return expression.len >= 2;

    if (std.mem.eql(u8, expression, "true") or
        std.mem.eql(u8, expression, "false") or
        std.mem.eql(u8, expression, "null") or
        std.mem.eql(u8, expression, "undefined")) return true;

    var seen_digit = false;
    var seen_dot = false;
    for (expression, 0..) |ch, idx| {
        if (idx == 0 and (ch == '+' or ch == '-')) continue;
        if (std.ascii.isDigit(ch)) {
            seen_digit = true;
            continue;
        }
        if (ch == '.' and !seen_dot) {
            seen_dot = true;
            continue;
        }
        return false;
    }
    return seen_digit;
}

fn isSimpleAccessExpression(expression: []const u8) bool {
    var cursor: usize = 0;
    if (!consumeIdentifier(expression, &cursor)) return false;
    while (cursor < expression.len) {
        if (expression[cursor] != '.') return false;
        cursor += 1;
        if (!consumeIdentifier(expression, &cursor)) return false;
    }
    return true;
}

fn consumeIdentifier(expression: []const u8, cursor: *usize) bool {
    if (cursor.* >= expression.len or !isIdentStart(expression[cursor.*])) return false;
    cursor.* += 1;
    while (cursor.* < expression.len and isIdentContinue(expression[cursor.*])) cursor.* += 1;
    return true;
}

fn scanQuotedString(expression: []const u8, start: usize) ?usize {
    const quote = expression[start];
    var cursor = start + 1;
    while (cursor < expression.len) : (cursor += 1) {
        if (expression[cursor] == '\\') {
            cursor += 1;
            continue;
        }
        if (expression[cursor] == quote) return cursor;
    }
    return null;
}

fn isSupportedExpressionPunctuation(ch: u8) bool {
    return switch (ch) {
        '.', '(', ')', '[', ']', '?', ':', '!', '=', '>', '<', '&', '|', '+', '-', '*', '/', '%', ',' => true,
        else => false,
    };
}

fn splitCallArguments(source: []const u8, out: *std.ArrayList([]const u8)) !void {
    var start: usize = 0;
    var depth_paren: usize = 0;
    var depth_bracket: usize = 0;
    var depth_brace: usize = 0;
    var cursor: usize = 0;
    while (cursor < source.len) : (cursor += 1) {
        const ch = source[cursor];
        if (ch == '\'' or ch == '"') {
            cursor = scanQuotedString(source, cursor) orelse return error.InvalidCharacter;
            continue;
        }
        switch (ch) {
            '(' => depth_paren += 1,
            ')' => {
                if (depth_paren > 0) depth_paren -= 1;
            },
            '[' => depth_bracket += 1,
            ']' => {
                if (depth_bracket > 0) depth_bracket -= 1;
            },
            '{' => depth_brace += 1,
            '}' => {
                if (depth_brace > 0) depth_brace -= 1;
            },
            ',' => {
                if (depth_paren == 0 and depth_bracket == 0 and depth_brace == 0) {
                    try out.append(std.heap.page_allocator, source[start..cursor]);
                    start = cursor + 1;
                }
            },
            else => {},
        }
    }
    try out.append(std.heap.page_allocator, source[start..]);
}

fn findMatchingParenForward(source: []const u8, open_paren: usize) ?usize {
    var depth: usize = 0;
    var cursor = open_paren;
    while (cursor < source.len) : (cursor += 1) {
        const ch = source[cursor];
        if (ch == '\'' or ch == '"') {
            cursor = scanQuotedString(source, cursor) orelse return null;
            continue;
        }
        if (ch == '(') {
            depth += 1;
            continue;
        }
        if (ch == ')') {
            depth -= 1;
            if (depth == 0) return cursor;
        }
    }
    return null;
}
