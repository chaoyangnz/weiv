const std = @import("std");
const template = @import("../parser/template/index.zig");
const sfc = @import("../parser/sfc.zig");
const sir = @import("sir.zig");
const slot_manifest = @import("slot_manifest.zig");

pub const TemplateBindings = sir.TemplateBindings;
pub const ComponentRef = sir.ComponentRef;
pub const Diagnostic = sir.TemplateBindingDiagnostic;

const Scope = struct {
    names: []const []const u8,

    fn contains(self: Scope, name: []const u8) bool {
        for (self.names) |local_name| {
            if (std.mem.eql(u8, local_name, name)) return true;
        }
        return false;
    }
};

pub fn bind(
    document: *const template.NormalizedDocument,
    script: *const sir.ScriptFacts,
    provider: *slot_manifest.Provider,
    allocator: std.mem.Allocator,
) anyerror!TemplateBindings {
    var component_refs = std.ArrayList(ComponentRef).empty;
    defer component_refs.deinit(allocator);
    var diagnostics = std.ArrayList(Diagnostic).empty;
    defer diagnostics.deinit(allocator);
    var expressions = std.ArrayList(sir.ExpressionFacts).empty;
    defer {
        for (expressions.items) |expression| allocator.free(expression.references);
        expressions.deinit(allocator);
    }
    var scopes = std.ArrayList(Scope).empty;
    defer scopes.deinit(allocator);

    const manifest_result = try slot_manifest.build(document, allocator);
    defer {
        for (manifest_result.duplicates) |dup| {
            if (dup.name) |n| allocator.free(n);
        }
        allocator.free(manifest_result.duplicates);
    }

    for (manifest_result.duplicates) |dup| {
        const name_for_diag = dup.name orelse "default";
        try appendDiagnostic(&diagnostics, "slot.duplicate_outlet", name_for_diag, "Slot outlet declared more than once with the same name", dup.span, allocator);
    }

    try validateFrameworkBindings(script, &diagnostics, allocator);
    try validateStateModelDiagnostics(script, &diagnostics, allocator);

    try bindNodes(document.nodes, script, &component_refs, &diagnostics, &expressions, &scopes, provider, allocator);

    return .{
        .component_refs = try component_refs.toOwnedSlice(allocator),
        .expressions = try expressions.toOwnedSlice(allocator),
        .diagnostics = try diagnostics.toOwnedSlice(allocator),
        .own_slot_manifest = manifest_result.manifest,
    };
}

fn validateFrameworkBindings(
    script: *const sir.ScriptFacts,
    diagnostics: *std.ArrayList(Diagnostic),
    allocator: std.mem.Allocator,
) !void {
    for (script.bindings) |binding| {
        if (std.mem.eql(u8, binding.name, "emit")) {
            try appendDiagnostic(
                diagnostics,
                "framework.reserved_binding",
                "emit",
                "`emit` is provided by Weiv for component events; declare `export interface Emits` for typing instead of defining `emit` yourself",
                .{ .start = binding.span_start, .end = binding.span_end },
                allocator,
            );
        }
        if (std.mem.eql(u8, binding.name, "weivUpdate")) {
            try appendDiagnostic(
                diagnostics,
                "framework.reserved_binding",
                "weivUpdate",
                "`weivUpdate` is provided by Weiv for external callback updates; do not declare a binding with this name",
                .{ .start = binding.span_start, .end = binding.span_end },
                allocator,
            );
        }
    }
}

fn validateStateModelDiagnostics(
    script: *const sir.ScriptFacts,
    diagnostics: *std.ArrayList(Diagnostic),
    allocator: std.mem.Allocator,
) !void {
    for (script.state_facts.mutations) |mutation| {
        if (findAliasTarget(script, mutation.binding)) |target| {
            if (isVisibleBinding(target, script)) {
                try appendDiagnostic(
                    diagnostics,
                    "alias.mutation",
                    target,
                    "Mutation through a local alias is only shallowly tracked today, so Weiv will treat this site conservatively",
                    .{ .start = mutation.span_start, .end = mutation.span_end },
                    allocator,
                );
            }
            continue;
        }

        if (!isVisibleBinding(mutation.binding, script)) continue;

        if (!mutation.statement_position) {
            try appendDiagnostic(
                diagnostics,
                "mutation.expression_position",
                mutation.binding,
                "Mutation is nested inside a larger expression, so Weiv will treat this site conservatively",
                .{ .start = mutation.span_start, .end = mutation.span_end },
                allocator,
            );
            continue;
        }

        if (mutation.inside_callback and !mutation.callback_owned_candidate) {
            try appendDiagnostic(
                diagnostics,
                "callback.unowned_mutation",
                mutation.binding,
                "Mutation happens inside a callback boundary that Weiv does not own; local state may change without updating the DOM. Wrap the mutation in weivUpdate(() => { ... })",
                .{ .start = mutation.span_start, .end = mutation.span_end },
                allocator,
            );
            continue;
        }
    }
}

fn bindNodes(
    nodes: []const template.NormalizedNode,
    script: *const sir.ScriptFacts,
    component_refs: *std.ArrayList(ComponentRef),
    diagnostics: *std.ArrayList(Diagnostic),
    expressions: *std.ArrayList(sir.ExpressionFacts),
    scopes: *std.ArrayList(Scope),
    provider: *slot_manifest.Provider,
    allocator: std.mem.Allocator,
) anyerror!void {
    for (nodes) |node| {
        switch (node) {
            .text => {},
            .interpolation => |interp| try bindExpression(interp.expression, interp.span, script, diagnostics, expressions, scopes.items, allocator),
            .slot_outlet => |slot_outlet| {
                try bindNodes(slot_outlet.fallback_children, script, component_refs, diagnostics, expressions, scopes, provider, allocator);
            },
            .conditional => |conditional| {
                try bindExpression(conditional.condition, conditional.span, script, diagnostics, expressions, scopes.items, allocator);
                try bindNodes(conditional.consequent, script, component_refs, diagnostics, expressions, scopes, provider, allocator);
                try bindNodes(conditional.alternate, script, component_refs, diagnostics, expressions, scopes, provider, allocator);
            },
            .for_loop => |for_loop| {
                try bindExpression(for_loop.iterable_expr, for_loop.span, script, diagnostics, expressions, scopes.items, allocator);
                var loop_scope_names = [1][]const u8{for_loop.item_name};
                try scopes.append(allocator, .{ .names = loop_scope_names[0..1] });
                defer _ = scopes.pop();
                try bindNodes(for_loop.body, script, component_refs, diagnostics, expressions, scopes, provider, allocator);
            },
            .element => |element| try bindElement(&element, script, component_refs, diagnostics, expressions, scopes, provider, allocator),
        }
    }
}

fn bindElement(
    element: *const template.normalized.ElementNode,
    script: *const sir.ScriptFacts,
    component_refs: *std.ArrayList(ComponentRef),
    diagnostics: *std.ArrayList(Diagnostic),
    expressions: *std.ArrayList(sir.ExpressionFacts),
    scopes: *std.ArrayList(Scope),
    provider: *slot_manifest.Provider,
    allocator: std.mem.Allocator,
) anyerror!void {
    for (element.attributes) |attribute| {
        if (std.mem.eql(u8, attribute.name, "v-if")) {
            try appendDiagnostic(
                diagnostics,
                "directive.vue_structural_syntax",
                attribute.name,
                "v-if is an inert HTML attribute in Weiv; use #if for a structural conditional",
                attribute.span,
                allocator,
            );
        } else if (std.mem.eql(u8, attribute.name, "v-for")) {
            try appendDiagnostic(
                diagnostics,
                "directive.vue_structural_syntax",
                attribute.name,
                "v-for is an inert HTML attribute in Weiv; use #for for a structural loop",
                attribute.span,
                allocator,
            );
        }
    }

    if (isComponentTag(element.tag_name)) {
        const resolved = isNameVisible(element.tag_name, script, scopes.items);
        try component_refs.append(allocator, .{
            .tag_name = element.tag_name,
            .resolved = resolved,
            .span = element.span,
        });
        if (!resolved) {
            try appendDiagnostic(diagnostics, "unresolved_component", element.tag_name, "Unresolved component tag", element.span, allocator);
        }
    }

    for (element.directives) |directive| {
        switch (directive) {
            .bind => |bind_dir| {
                if (bind_dir.deprecated_syntax) {
                    try appendDiagnostic(
                        diagnostics,
                        "directive.deprecated_syntax",
                        bind_dir.target_name,
                        "bind: is deprecated; use the canonical :name binding syntax",
                        bind_dir.span,
                        allocator,
                    );
                }
                try bindExpression(bind_dir.expression, element.span, script, diagnostics, expressions, scopes.items, allocator);
            },
            .event => |event_dir| {
                if (event_dir.deprecated_syntax) {
                    try appendDiagnostic(
                        diagnostics,
                        "directive.deprecated_syntax",
                        event_dir.event_name,
                        "on: is deprecated; use the canonical @event syntax",
                        event_dir.span,
                        allocator,
                    );
                }
                try bindExpression(event_dir.expression, element.span, script, diagnostics, expressions, scopes.items, allocator);
            },
            // slot:name placement (and <template slot:foo> placement) is enforced
            // as a hard error at parser/lower time in src/compiler/lower/lower.zig.
            // The binder no longer needs to re-check it.
            .slot_assign => {},
            .if_expr, .else_branch, .for_expr => unreachable,
        }
    }

    if (isComponentTag(element.tag_name)) {
        var seen = std.StringHashMap(bool).init(allocator);
        defer seen.deinit();
        for (element.children) |child| {
            switch (child) {
                .element => |child_el| {
                    for (child_el.directives) |dir| {
                        if (dir == .slot_assign) {
                            const sa = dir.slot_assign;
                            const is_template_group = std.mem.eql(u8, child_el.tag_name, "template");
                            if (seen.get(sa.slot_name)) |previous_was_template| {
                                if (!(previous_was_template and is_template_group)) {
                                    try appendDiagnostic(diagnostics, "slot.duplicate_provision", sa.slot_name, "Slot is provided more than once; use <template slot:<name>> to group multi-node content", sa.span, allocator);
                                }
                            }
                            try seen.put(sa.slot_name, is_template_group);
                        }
                    }
                },
                else => {},
            }
        }

        // Cross-component slot validation: check that provided slots exist in the child manifest.
        if (try provider.manifestFor(element.tag_name)) |child_manifest| {
            var has_unnamed_content = false;
            for (element.children) |child| {
                switch (child) {
                    .element => |child_el| {
                        var has_slot_assign = false;
                        for (child_el.directives) |dir| {
                            if (dir == .slot_assign) {
                                has_slot_assign = true;
                                const sa = dir.slot_assign;
                                if (!child_manifest.hasName(sa.slot_name)) {
                                    try appendDiagnostic(diagnostics, "slot.unknown_name", sa.slot_name, "Child component has no <slot> with this name", sa.span, allocator);
                                }
                            }
                        }
                        if (!has_slot_assign) has_unnamed_content = true;
                    },
                    .text => |t| {
                        if (!isWhitespaceOnly(t.content)) has_unnamed_content = true;
                    },
                    .interpolation => has_unnamed_content = true,
                    else => has_unnamed_content = true,
                }
            }
            if (has_unnamed_content and !child_manifest.hasDefault()) {
                try appendDiagnostic(diagnostics, "slot.default_not_supported", element.tag_name, "Component has no default <slot>; default content is not allowed", element.span, allocator);
            }
        }
    }

    try bindNodes(element.children, script, component_refs, diagnostics, expressions, scopes, provider, allocator);
}

fn isWhitespaceOnly(s: []const u8) bool {
    for (s) |b| {
        if (b != ' ' and b != '\t' and b != '\n' and b != '\r') return false;
    }
    return true;
}

fn bindExpression(
    expression: []const u8,
    span: sfc.Span,
    script: *const sir.ScriptFacts,
    diagnostics: *std.ArrayList(Diagnostic),
    expressions: *std.ArrayList(sir.ExpressionFacts),
    scopes: []const Scope,
    allocator: std.mem.Allocator,
) anyerror!void {
    var references = std.ArrayList(sir.ExpressionReference).empty;
    defer references.deinit(allocator);
    var seen = std.StringHashMap(void).init(allocator);
    defer seen.deinit();

    var i: usize = 0;
    var in_quote: ?u8 = null;
    var template_depth: usize = 0;
    while (i < expression.len) {
        if (in_quote) |quote| {
            if (expression[i] == '\\' and i + 1 < expression.len) {
                i += 2;
                continue;
            }
            if (quote == '`' and expression[i] == '$' and i + 1 < expression.len and expression[i + 1] == '{') {
                template_depth += 1;
                in_quote = null;
                i += 2;
                continue;
            }
            if (expression[i] == quote) {
                in_quote = null;
            }
            i += 1;
            continue;
        }

        if (template_depth > 0 and expression[i] == '}') {
            template_depth -= 1;
            in_quote = '`';
            i += 1;
            continue;
        }

        if (expression[i] == '"' or expression[i] == '\'' or expression[i] == '`') {
            in_quote = expression[i];
            i += 1;
            continue;
        }
        if (!isIdentifierStart(expression[i])) {
            i += 1;
            continue;
        }

        const start = i;
        i += 1;
        while (i < expression.len and isIdentifierContinue(expression[i])) : (i += 1) {}
        const ident = expression[start..i];
        const is_call = nextNonSpaceIs(expression, i, '(');

        if (isKeyword(ident)) continue;
        if (isPropertyAccessExpression(expression, start)) continue;
        if (seen.contains(ident)) {
            if (is_call) {
                for (references.items) |*reference| {
                    if (std.mem.eql(u8, reference.name, ident)) reference.call = true;
                }
            }
            continue;
        }
        try seen.put(ident, {});
        if (isNameVisible(ident, script, scopes)) {
            try references.append(allocator, .{ .name = ident, .call = is_call });
        }

        if (is_call) {
            if (findVisibleHelper(script, ident)) |helper| {
                const ident_span = sfc.Span{
                    .start = span.start + start,
                    .end = span.start + i,
                };
                if (helper.contains_external_reads) {
                    try appendDiagnostic(
                        diagnostics,
                        "helper.external_state",
                        ident,
                        "Local helper reads external state, so Weiv will treat this template call conservatively",
                        ident_span,
                        allocator,
                    );
                } else if (helper.contains_side_effects) {
                    try appendDiagnostic(
                        diagnostics,
                        "helper.side_effects",
                        ident,
                        "Local helper has side effects, so Weiv will treat this template call conservatively",
                        ident_span,
                        allocator,
                    );
                }
            }
        }

        if (!isNameVisible(ident, script, scopes)) {
            const ident_span = sfc.Span{
                .start = span.start + start,
                .end = span.start + i,
            };
            try appendDiagnostic(diagnostics, "unresolved_binding", ident, "Unresolved template binding", ident_span, allocator);
        }
    }
    const owned_references = try references.toOwnedSlice(allocator);
    errdefer allocator.free(owned_references);
    try expressions.append(allocator, .{
        .source = expression,
        .references = owned_references,
    });
}

fn appendDiagnostic(
    diagnostics: *std.ArrayList(Diagnostic),
    kind: []const u8,
    name: []const u8,
    message: []const u8,
    span: sfc.Span,
    allocator: std.mem.Allocator,
) anyerror!void {
    try diagnostics.append(allocator, .{
        .severity = try allocator.dupe(u8, classifyDiagnosticSeverity(kind)),
        .kind = try allocator.dupe(u8, kind),
        .name = try allocator.dupe(u8, name),
        .message = try allocator.dupe(u8, message),
        .span = span,
    });
}

fn classifyDiagnosticSeverity(kind: []const u8) []const u8 {
    if (std.mem.eql(u8, kind, "framework.reserved_binding")) return "error";
    if (std.mem.eql(u8, kind, "unresolved_binding")) return "error";
    if (std.mem.eql(u8, kind, "unresolved_component")) return "error";
    if (std.mem.startsWith(u8, kind, "slot.")) return "error";
    if (std.mem.eql(u8, kind, "helper.external_state")) return "warning";
    if (std.mem.eql(u8, kind, "helper.side_effects")) return "warning";
    if (std.mem.eql(u8, kind, "mutation.expression_position")) return "warning";
    if (std.mem.eql(u8, kind, "callback.unowned_mutation")) return "warning";
    if (std.mem.eql(u8, kind, "alias.mutation")) return "warning";
    if (std.mem.eql(u8, kind, "directive.deprecated_syntax")) return "warning";
    if (std.mem.eql(u8, kind, "directive.vue_structural_syntax")) return "warning";
    return "info";
}

fn isNameVisible(name: []const u8, script: *const sir.ScriptFacts, scopes: []const Scope) bool {
    if (std.mem.eql(u8, name, "emit")) return true;

    var idx = scopes.len;
    while (idx > 0) {
        idx -= 1;
        if (scopes[idx].contains(name)) return true;
    }

    for (script.bindings) |binding| {
        if (binding.template_visible and std.mem.eql(u8, binding.name, name)) return true;
    }
    return false;
}

fn findVisibleHelper(script: *const sir.ScriptFacts, name: []const u8) ?sir.HelperFacts {
    for (script.bindings) |binding| {
        if (!binding.template_visible or !binding.callable) continue;
        if (!std.mem.eql(u8, binding.name, name)) continue;
        for (script.state_facts.helpers) |helper| {
            if (std.mem.eql(u8, helper.name, name)) return helper;
        }
        return null;
    }
    return null;
}

fn findAliasTarget(script: *const sir.ScriptFacts, alias_name: []const u8) ?[]const u8 {
    for (script.state_facts.aliases) |alias| {
        if (std.mem.eql(u8, alias.alias, alias_name)) return alias.target;
    }
    return null;
}

fn isVisibleBinding(name: []const u8, script: *const sir.ScriptFacts) bool {
    for (script.bindings) |binding| {
        if (binding.template_visible and std.mem.eql(u8, binding.name, name)) return true;
    }
    return false;
}

fn isComponentTag(tag_name: []const u8) bool {
    if (tag_name.len == 0) return false;
    return std.ascii.isUpper(tag_name[0]);
}

fn isIdentifierStart(char: u8) bool {
    return std.ascii.isAlphabetic(char) or char == '_' or char == '$';
}

fn isIdentifierContinue(char: u8) bool {
    return isIdentifierStart(char) or std.ascii.isDigit(char);
}

fn nextNonSpaceIs(expr: []const u8, idx: usize, expected: u8) bool {
    var cursor = idx;
    while (cursor < expr.len) : (cursor += 1) {
        if (expr[cursor] == ' ' or expr[cursor] == '\n' or expr[cursor] == '\r' or expr[cursor] == '\t') continue;
        return expr[cursor] == expected;
    }
    return false;
}

fn isPropertyAccessExpression(expr: []const u8, ident_start: usize) bool {
    var cursor = ident_start;
    while (cursor > 0) {
        cursor -= 1;
        if (expr[cursor] == ' ' or expr[cursor] == '\n' or expr[cursor] == '\r' or expr[cursor] == '\t') continue;
        return expr[cursor] == '.' and !(cursor >= 2 and std.mem.eql(u8, expr[cursor - 2 .. cursor + 1], "..."));
    }
    return false;
}

fn isKeyword(value: []const u8) bool {
    return std.mem.eql(u8, value, "true") or
        std.mem.eql(u8, value, "false") or
        std.mem.eql(u8, value, "null") or
        std.mem.eql(u8, value, "undefined") or
        std.mem.eql(u8, value, "in") or
        std.mem.eql(u8, value, "typeof") or
        std.mem.eql(u8, value, "return");
}
