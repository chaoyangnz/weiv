const std = @import("std");
const script_facts = @import("../compiler/sema/script_facts.zig");

const backend = struct {
    extern fn weiv_script_analyze(source: [*:0]const u8, source_path: [*:0]const u8) ?[*:0]u8;
    extern fn weiv_analyze_module_state(source: [*:0]const u8, source_path: [*:0]const u8) ?[*:0]u8;
    extern fn weiv_transpile_module(source: [*:0]const u8, source_path: [*:0]const u8) ?[*:0]u8;
    extern fn weiv_cell_expression_supported(source: [*:0]const u8) bool;
    extern fn weiv_cell_handler_supported(source: [*:0]const u8) bool;
    extern fn weiv_cell_handler_kind(source: [*:0]const u8) u8;
    extern fn weiv_cell_script_diagnostics(source: [*:0]const u8, path: [*:0]const u8, bindings: [*:0]const u8, module: bool) ?[*:0]u8;
    extern fn weiv_lower_cells_with_expressions(source: [*:0]const u8, path: [*:0]const u8, bindings: [*:0]const u8, expressions: [*:0]const u8) ?[*:0]u8;
    extern fn weiv_lower_cells(source: [*:0]const u8, source_path: [*:0]const u8, bindings: [*:0]const u8) ?[*:0]u8;
    extern fn weiv_lower_module_cells(source: [*:0]const u8, source_path: [*:0]const u8, companion: [*:0]const u8, bindings: [*:0]const u8) ?[*:0]u8;
    extern fn weiv_rewrite_expression(expression: [*:0]const u8, scope_bindings_json: [*:0]const u8, scope_prefix: [*:0]const u8) ?[*:0]u8;
    extern fn weiv_backend_free(ptr: [*:0]u8) void;
};

pub fn lowerModuleCells(source: []const u8, path: []const u8, companion: []const u8, bindings: []const u8, allocator: std.mem.Allocator) ![]u8 {
    const source_z = try allocator.dupeZ(u8, source);
    defer allocator.free(source_z);
    const path_z = try allocator.dupeZ(u8, path);
    defer allocator.free(path_z);
    const companion_z = try allocator.dupeZ(u8, companion);
    defer allocator.free(companion_z);
    const bindings_z = try allocator.dupeZ(u8, bindings);
    defer allocator.free(bindings_z);
    const result = backend.weiv_lower_module_cells(source_z.ptr, path_z.ptr, companion_z.ptr, bindings_z.ptr) orelse return error.ModuleCellBackendFailure;
    defer backend.weiv_backend_free(result);
    const parsed = try std.json.parseFromSlice(struct { code: []const u8, @"error": ?[]const u8 }, allocator, std.mem.span(result), .{});
    defer parsed.deinit();
    if (parsed.value.@"error" != null) return error.ModuleCellLoweringUnsupported;
    return allocator.dupe(u8, parsed.value.code);
}

pub fn lowerCells(source: []const u8, path: []const u8, bindings: []const u8, allocator: std.mem.Allocator) ![]u8 {
    return lowerCellsWithExpressions(source, path, bindings, "", allocator);
}

pub fn lowerCellsWithExpressions(source: []const u8, path: []const u8, bindings: []const u8, expressions: []const u8, allocator: std.mem.Allocator) ![]u8 {
    const source_z = try allocator.dupeZ(u8, source);
    defer allocator.free(source_z);
    const path_z = try allocator.dupeZ(u8, path);
    defer allocator.free(path_z);
    const bindings_z = try allocator.dupeZ(u8, bindings);
    defer allocator.free(bindings_z);
    const expressions_z = try allocator.dupeZ(u8, expressions);
    defer allocator.free(expressions_z);
    const result = backend.weiv_lower_cells_with_expressions(source_z.ptr, path_z.ptr, bindings_z.ptr, expressions_z.ptr) orelse return error.CellBackendFailure;
    defer backend.weiv_backend_free(result);
    const parsed = try std.json.parseFromSlice(struct { code: []const u8, @"error": ?[]const u8 }, allocator, std.mem.span(result), .{});
    defer parsed.deinit();
    if (parsed.value.@"error") |reason| {
        return cellLoweringError(reason);
    }
    return allocator.dupe(u8, parsed.value.code);
}

pub fn cellLoweringError(reason: []const u8) anyerror {
    if (std.mem.eql(u8, reason, "assignment_pattern")) return error.CellAssignmentPatternUnsupported;
    if (std.mem.eql(u8, reason, "declaration_kind")) return error.CellVarDeclarationUnsupported;
    if (std.mem.eql(u8, reason, "dynamic_eval")) return error.CellDynamicEvalUnsupported;
    if (std.mem.eql(u8, reason, "top_level_await")) return error.CellTopLevelAwaitUnsupported;
    if (std.mem.eql(u8, reason, "ambient_declaration")) return error.CellAmbientDeclarationUnsupported;
    if (std.mem.eql(u8, reason, "const_assignment")) return error.CellConstAssignmentUnsupported;
    if (std.mem.eql(u8, reason, "reserved_identifier")) return error.CellReservedIdentifier;
    if (std.mem.eql(u8, reason, "template_untracked_assignment")) return error.CellTemplateUntrackedAssignmentUnsupported;
    if (std.mem.eql(u8, reason, "component_default_export")) return error.CellComponentDefaultExportUnsupported;
    return error.CellDeclarationUnsupported;
}

pub fn cellScriptDiagnosticsRaw(source: []const u8, path: []const u8, names: []const u8, module: bool, allocator: std.mem.Allocator) ![]u8 {
    const source_z = try allocator.dupeZ(u8, source);
    defer allocator.free(source_z);
    const path_z = try allocator.dupeZ(u8, path);
    defer allocator.free(path_z);
    const names_z = try allocator.dupeZ(u8, names);
    defer allocator.free(names_z);
    const result = backend.weiv_cell_script_diagnostics(source_z.ptr, path_z.ptr, names_z.ptr, module) orelse return error.CellBackendFailure;
    defer backend.weiv_backend_free(result);
    return allocator.dupe(u8, std.mem.span(result));
}

pub fn analyzeScriptRaw(
    source: []const u8,
    source_path: []const u8,
    allocator: std.mem.Allocator,
) ![]u8 {
    const source_z = try allocator.dupeZ(u8, source);
    defer allocator.free(source_z);

    const path_z = try allocator.dupeZ(u8, source_path);
    defer allocator.free(path_z);

    const result_ptr = backend.weiv_script_analyze(source_z.ptr, path_z.ptr) orelse return error.BackendFailure;
    defer backend.weiv_backend_free(result_ptr);

    const json = std.mem.span(result_ptr);
    return try allocator.dupe(u8, json);
}

pub fn analyzeModuleStateRaw(source: []const u8, source_path: []const u8, allocator: std.mem.Allocator) ![]u8 {
    const source_z = try allocator.dupeZ(u8, source);
    defer allocator.free(source_z);
    const path_z = try allocator.dupeZ(u8, source_path);
    defer allocator.free(path_z);
    const result = backend.weiv_analyze_module_state(source_z.ptr, path_z.ptr) orelse return error.BackendFailure;
    defer backend.weiv_backend_free(result);
    return allocator.dupe(u8, std.mem.span(result));
}

pub fn analyzeScript(
    source: []const u8,
    source_path: []const u8,
    allocator: std.mem.Allocator,
) !script_facts.ParsedScript {
    const json = try analyzeScriptRaw(source, source_path, allocator);
    defer allocator.free(json);
    return try script_facts.parseFromJson(json, allocator);
}

pub fn rewriteExpression(
    expression: []const u8,
    scope_bindings_json: []const u8,
    scope_prefix: []const u8,
    allocator: std.mem.Allocator,
) ![]u8 {
    const expr_z = try allocator.dupeZ(u8, expression);
    defer allocator.free(expr_z);

    const bindings_z = try allocator.dupeZ(u8, scope_bindings_json);
    defer allocator.free(bindings_z);

    const prefix_z = try allocator.dupeZ(u8, scope_prefix);
    defer allocator.free(prefix_z);

    const result_ptr = backend.weiv_rewrite_expression(expr_z.ptr, bindings_z.ptr, prefix_z.ptr) orelse return error.ExpressionRewriteFailed;
    defer backend.weiv_backend_free(result_ptr);

    const result = std.mem.span(result_ptr);
    return try allocator.dupe(u8, result);
}

pub fn transpileModule(
    source: []const u8,
    source_path: []const u8,
    allocator: std.mem.Allocator,
) ![]u8 {
    const source_z = try allocator.dupeZ(u8, source);
    defer allocator.free(source_z);

    const path_z = try allocator.dupeZ(u8, source_path);
    defer allocator.free(path_z);

    const result_ptr = backend.weiv_transpile_module(source_z.ptr, path_z.ptr) orelse return error.BackendFailure;
    defer backend.weiv_backend_free(result_ptr);

    const js = std.mem.span(result_ptr);
    return try allocator.dupe(u8, js);
}

pub fn validateCellExpression(source: []const u8, allocator: std.mem.Allocator) !void {
    const source_z = try allocator.dupeZ(u8, source);
    defer allocator.free(source_z);
    if (!backend.weiv_cell_expression_supported(source_z.ptr)) return error.CellTemplateMutationUnsupported;
}

pub fn validateCellHandlerExpression(source: []const u8, allocator: std.mem.Allocator) !void {
    const source_z = try allocator.dupeZ(u8, source);
    defer allocator.free(source_z);
    if (!backend.weiv_cell_handler_supported(source_z.ptr)) return error.CellTemplateExpressionUnsupported;
}

pub fn cellHandlerKind(source: []const u8, allocator: std.mem.Allocator) !u8 {
    const source_z = try allocator.dupeZ(u8, source);
    defer allocator.free(source_z);
    return backend.weiv_cell_handler_kind(source_z.ptr);
}
