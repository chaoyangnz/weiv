const std = @import("std");
const compiler_diagnostics = @import("diagnostics.zig");
const binding = @import("sema/binder.zig");
const lower = @import("lower/index.zig");
const component_unit = @import("component_unit.zig");
const parser = @import("parser/index.zig");
const slot_resolver = @import("project/slot_resolver.zig");
const script_backend = @import("../ffi/script_backend.zig");

pub fn compile(
    source: []const u8,
    source_path: []const u8,
    allocator: std.mem.Allocator,
) !component_unit.ComponentUnit {
    var report = try compileReport(source, source_path, allocator);
    defer report.deinit(allocator);
    if (report.halt_error) |err| return err;
    return try report.takeUnit(allocator);
}

pub fn compileReport(
    source: []const u8,
    source_path: []const u8,
    allocator: std.mem.Allocator,
) !component_unit.ComponentCompileReport {
    var bag = compiler_diagnostics.DiagnosticBag.init();
    defer bag.deinit(allocator);

    const owned = blk: {
        const source_copy = try allocator.dupe(u8, source);
        errdefer allocator.free(source_copy);
        const path_copy = try allocator.dupe(u8, source_path);
        break :blk .{ .source = source_copy, .path = path_copy };
    };
    var report = component_unit.ComponentCompileReport{
        .source_path = owned.path,
        .source = owned.source,
        .diagnostics = &.{},
        .sfc_document = null,
        .template_document = null,
        .normalized_template = null,
        .script = null,
        .script_js = null,
        .template_bindings = null,
        .lir_document = null,
        .halted_after = null,
        .halt_error = null,
    };
    errdefer report.deinit(allocator);

    const sfc_document = parser.parseSfc(owned.source) catch |err| {
        try compiler_diagnostics.appendSfcDiagnostic(&bag, source_path, err, allocator);
        report.diagnostics = try bag.toOwnedSlice(allocator);
        report.halted_after = .sfc_parse;
        report.halt_error = err;
        return report;
    };
    report.sfc_document = sfc_document;

    var template_document = parser.parseTemplate(sfc_document.template.content, allocator) catch |err| {
        try compiler_diagnostics.appendTemplateParseDiagnostic(&bag, source, source_path, sfc_document, err, allocator);
        report.diagnostics = try bag.toOwnedSlice(allocator);
        report.halted_after = .template_parse;
        report.halt_error = err;
        return report;
    };
    report.template_document = template_document;

    var normalized_template = parser.normalizeTemplate(&template_document, allocator) catch |err| {
        try compiler_diagnostics.appendTemplateNormalizeDiagnostic(&bag, source, source_path, sfc_document, template_document, err, allocator);
        report.diagnostics = try bag.toOwnedSlice(allocator);
        report.halted_after = .template_normalize;
        report.halt_error = err;
        return report;
    };
    report.normalized_template = normalized_template;

    const parsed_script = try script_backend.analyzeScript(sfc_document.script.content, source_path, allocator);
    report.script = parsed_script.facts;
    report.script_js = parsed_script.transpiled_code;
    try compiler_diagnostics.appendScriptDiagnostics(&bag, source, source_path, sfc_document, &report.script.?, allocator);
    if (!report.script.?.ok) {
        report.diagnostics = try bag.toOwnedSlice(allocator);
        report.halted_after = .script_facts;
        report.halt_error = error.InvalidScript;
        return report;
    }

    var resolver = slot_resolver.NeighbourSlotResolver.init(allocator, source_path, &report.script.?);
    defer resolver.deinit();
    var provider = resolver.provider();
    var template_bindings = try binding.bind(&normalized_template, &report.script.?, &provider, allocator);
    try compiler_diagnostics.appendBindingDiagnostics(&bag, source, source_path, &template_bindings, allocator);
    report.template_bindings = template_bindings;

    const lir_document = lower.lower(&normalized_template, &template_bindings, allocator) catch |err| {
        try compiler_diagnostics.appendLoweringDiagnostic(&bag, source, source_path, sfc_document, normalized_template, err, allocator);
        report.diagnostics = try bag.toOwnedSlice(allocator);
        report.halted_after = .lowering;
        report.halt_error = err;
        return report;
    };
    report.lir_document = lir_document;

    report.diagnostics = try bag.toOwnedSlice(allocator);
    return report;
}
