const std = @import("std");
const parser = @import("parser/index.zig");
const sir = @import("sema/sir.zig");

const sfc = parser.sfc;
const template = parser.template;

pub const Severity = enum {
    @"error",
    warning,
    info,
};

pub const Stage = enum {
    sfc_parse,
    template_parse,
    template_normalize,
    script_facts,
    binding,
    lowering,
    render_tree,
    emit,
    bundle,
};

pub const Span = struct {
    start: usize,
    end: usize,
};

pub const SourceLocation = struct {
    line: u32,
    column: u32,
};

pub const Diagnostic = struct {
    code: []const u8,
    severity: Severity,
    message: []const u8,
    stage: Stage,
    source_path: []const u8,
    span: ?Span,
    location: ?SourceLocation,
    fatal: bool,

    pub fn deinit(self: *Diagnostic, allocator: std.mem.Allocator) void {
        allocator.free(self.code);
        allocator.free(self.message);
        allocator.free(self.source_path);
    }
};

pub const DiagnosticBag = struct {
    diagnostics: std.ArrayList(Diagnostic),

    pub fn init() DiagnosticBag {
        return .{
            .diagnostics = .empty,
        };
    }

    pub fn deinit(self: *DiagnosticBag, allocator: std.mem.Allocator) void {
        for (self.diagnostics.items) |*diagnostic| diagnostic.deinit(allocator);
        self.diagnostics.deinit(allocator);
    }

    pub fn append(self: *DiagnosticBag, allocator: std.mem.Allocator, diagnostic: Diagnostic) !void {
        try self.diagnostics.append(allocator, diagnostic);
    }

    pub fn appendOwned(
        self: *DiagnosticBag,
        allocator: std.mem.Allocator,
        code: []const u8,
        severity: Severity,
        message: []const u8,
        stage: Stage,
        source_path: []const u8,
        span: ?Span,
        location: ?SourceLocation,
        fatal: bool,
    ) !void {
        try self.append(allocator, .{
            .code = try allocator.dupe(u8, code),
            .severity = severity,
            .message = try allocator.dupe(u8, message),
            .stage = stage,
            .source_path = try allocator.dupe(u8, source_path),
            .span = span,
            .location = location,
            .fatal = fatal,
        });
    }

    pub fn hasFatal(self: *const DiagnosticBag) bool {
        return hasFatalDiagnostics(self.diagnostics.items);
    }

    pub fn toOwnedSlice(self: *DiagnosticBag, allocator: std.mem.Allocator) ![]Diagnostic {
        return self.diagnostics.toOwnedSlice(allocator);
    }
};

pub fn hasFatalDiagnostics(diagnostics: []const Diagnostic) bool {
    for (diagnostics) |diagnostic| {
        if (diagnostic.fatal) return true;
    }
    return false;
}

pub fn severityFromString(value: []const u8) Severity {
    if (std.mem.eql(u8, value, "warning")) return .warning;
    if (std.mem.eql(u8, value, "info")) return .info;
    return .@"error";
}

pub fn severityLabel(severity: Severity) []const u8 {
    return switch (severity) {
        .@"error" => "error",
        .warning => "warning",
        .info => "info",
    };
}

pub fn stageLabel(stage: Stage) []const u8 {
    return switch (stage) {
        .sfc_parse => "sfc_parse",
        .template_parse => "template_parse",
        .template_normalize => "template_normalize",
        .script_facts => "script_facts",
        .binding => "binding",
        .lowering => "lowering",
        .render_tree => "render_tree",
        .emit => "emit",
        .bundle => "bundle",
    };
}

pub fn computeLocation(source: []const u8, span: Span) SourceLocation {
    var line: u32 = 1;
    var column: u32 = 1;
    var index: usize = 0;
    while (index < span.start and index < source.len) : (index += 1) {
        if (source[index] == '\n') {
            line += 1;
            column = 1;
        } else {
            column += 1;
        }
    }
    return .{
        .line = line,
        .column = column,
    };
}

pub fn appendSfcDiagnostic(
    bag: *DiagnosticBag,
    source_path: []const u8,
    err: anyerror,
    allocator: std.mem.Allocator,
) !void {
    const entry = switch (err) {
        error.MissingTemplate => .{ "sfc.missing_template", "Missing <template> section" },
        error.MissingScript => .{ "sfc.missing_script", "Missing <script lang=\"ts\"> section" },
        error.DuplicateTemplate => .{ "sfc.duplicate_template", "Duplicate <template> section" },
        error.DuplicateScript => .{ "sfc.duplicate_script", "Duplicate <script> section" },
        error.DuplicateStyle => .{ "sfc.duplicate_style", "Duplicate <style> section" },
        error.UnknownTopLevelSection => .{ "sfc.unknown_top_level_section", "Unknown top-level section; only template, script, and style are supported" },
        error.InvalidScriptAttributes => .{ "sfc.invalid_script_attributes", "Only <script lang=\"ts\"> is supported" },
        error.InvalidSectionOrder => .{ "sfc.invalid_section_order", "Sections must appear in template, script, style order" },
        error.UnterminatedOpenTag => .{ "sfc.unterminated_open_tag", "Unterminated top-level open tag" },
        error.UnterminatedCloseTag => .{ "sfc.unterminated_close_tag", "Unterminated top-level close tag" },
        else => return err,
    };
    try bag.appendOwned(allocator, entry[0], .@"error", entry[1], .sfc_parse, source_path, null, null, true);
}

pub fn appendTemplateParseDiagnostic(
    bag: *DiagnosticBag,
    source: []const u8,
    source_path: []const u8,
    sfc_document: sfc.Document,
    err: anyerror,
    allocator: std.mem.Allocator,
) !void {
    const entry = switch (err) {
        error.UnterminatedTag => .{ "template.unterminated_tag", "Unterminated template tag" },
        error.UnexpectedCloseTag => .{ "template.unexpected_close_tag", "Closing tag appeared without a matching open tag" },
        error.MismatchedCloseTag => .{ "template.mismatched_close_tag", "Closing tag does not match the currently open element" },
        error.InvalidSlotOutlet => .{ "template.invalid_slot_outlet", "<slot> only supports an optional name attribute and no directives" },
        error.InvalidDirective => .{ "template.invalid_directive", "Invalid template directive usage" },
        error.UnterminatedInterpolation => .{ "template.unterminated_interpolation", "Unterminated interpolation" },
        else => return err,
    };
    const absolute_span = sfc.Span{
        .start = sfc_document.template.content_span.start,
        .end = sfc_document.template.content_span.start + 1,
    };
    try bag.appendOwned(
        allocator,
        entry[0],
        .@"error",
        entry[1],
        .template_parse,
        source_path,
        .{ .start = absolute_span.start, .end = absolute_span.end },
        computeLocation(source, .{ .start = absolute_span.start, .end = absolute_span.end }),
        true,
    );
}

pub fn appendTemplateNormalizeDiagnostic(
    bag: *DiagnosticBag,
    source: []const u8,
    source_path: []const u8,
    sfc_document: sfc.Document,
    template_document: template.Document,
    err: anyerror,
    allocator: std.mem.Allocator,
) !void {
    const entry = switch (err) {
        error.UnexpectedElse => .{ "template.unexpected_else", "`else` must immediately follow a sibling element with `if`" },
        else => return err,
    };

    const relative_span = template.debug.findFirstInvalidNormalizeSpan(template_document.nodes, err) orelse sfc.Span{ .start = 0, .end = 1 };

    const absolute_span = Span{
        .start = sfc_document.template.content_span.start + relative_span.start,
        .end = sfc_document.template.content_span.start + relative_span.end,
    };

    try bag.appendOwned(
        allocator,
        entry[0],
        .@"error",
        entry[1],
        .template_normalize,
        source_path,
        absolute_span,
        computeLocation(source, absolute_span),
        true,
    );
}

pub fn appendLoweringDiagnostic(
    bag: *DiagnosticBag,
    source: []const u8,
    source_path: []const u8,
    sfc_document: sfc.Document,
    normalized_template: template.NormalizedDocument,
    err: anyerror,
    allocator: std.mem.Allocator,
) !void {
    const entry = switch (err) {
        error.InvalidSlotPlacement => .{ "template.invalid_slot_placement", "`slot:name` may only be used on direct children of a component usage" },
        error.InvalidSlotTemplatePlacement => .{ "template.invalid_slot_template_placement", "<template> grouping is only valid inside a component usage when paired with slot:name" },
        else => return err,
    };

    const relative_span = template.debug.findFirstInvalidLoweringSpan(normalized_template.nodes, err) orelse sfc.Span{ .start = 0, .end = 1 };
    const absolute_span = Span{
        .start = sfc_document.template.content_span.start + relative_span.start,
        .end = sfc_document.template.content_span.start + relative_span.end,
    };

    try bag.appendOwned(
        allocator,
        entry[0],
        .@"error",
        entry[1],
        .lowering,
        source_path,
        absolute_span,
        computeLocation(source, absolute_span),
        true,
    );
}

pub fn appendScriptDiagnostics(
    bag: *DiagnosticBag,
    source: []const u8,
    source_path: []const u8,
    sfc_document: sfc.Document,
    script: *const sir.ScriptFacts,
    allocator: std.mem.Allocator,
) !void {
    for (script.diagnostics) |diagnostic| {
        const absolute_span = Span{
            .start = sfc_document.script.content_span.start + diagnostic.span_start,
            .end = sfc_document.script.content_span.start + diagnostic.span_end,
        };
        try bag.appendOwned(
            allocator,
            diagnostic.code orelse "script.analysis",
            severityFromString(diagnostic.severity),
            diagnostic.message,
            .script_facts,
            source_path,
            absolute_span,
            computeLocation(source, absolute_span),
            !script.ok,
        );
    }
}

pub fn appendBindingDiagnostics(
    bag: *DiagnosticBag,
    source: []const u8,
    source_path: []const u8,
    template_bindings: *const sir.TemplateBindings,
    allocator: std.mem.Allocator,
) !void {
    for (template_bindings.diagnostics) |diagnostic| {
        const span = Span{
            .start = diagnostic.span.start,
            .end = diagnostic.span.end,
        };
        try bag.appendOwned(
            allocator,
            diagnostic.kind,
            severityFromString(diagnostic.severity),
            diagnostic.message,
            .binding,
            source_path,
            span,
            computeLocation(source, span),
            false,
        );
    }
}

pub fn writeTextDiagnostics(
    writer: anytype,
    diagnostics: []const Diagnostic,
    line_prefix: []const u8,
) !void {
    for (diagnostics) |diagnostic| {
        try writer.print("{s}{s} {s} [{s}]", .{
            line_prefix,
            severityLabel(diagnostic.severity),
            diagnostic.code,
            stageLabel(diagnostic.stage),
        });
        if (diagnostic.location) |location| {
            try writer.print(" [{d}:{d}]", .{ location.line, location.column });
        }
        if (diagnostic.span) |span| {
            try writer.print(" [{d}..{d}]", .{ span.start, span.end });
        }
        if (diagnostic.fatal) {
            try writer.writeAll(" fatal");
        }
        try writer.print(": {s}\n", .{diagnostic.message});
    }
}

pub fn writeJsonDiagnostics(
    writer: anytype,
    diagnostics: []const Diagnostic,
    item_indent: []const u8,
) !void {
    for (diagnostics, 0..) |diagnostic, index| {
        try writer.print("{s}{{\n", .{item_indent});
        try writer.print("{s}  \"code\": {f},\n", .{ item_indent, std.json.fmt(diagnostic.code, .{}) });
        try writer.print("{s}  \"severity\": {f},\n", .{ item_indent, std.json.fmt(severityLabel(diagnostic.severity), .{}) });
        try writer.print("{s}  \"stage\": {f},\n", .{ item_indent, std.json.fmt(stageLabel(diagnostic.stage), .{}) });
        try writer.print("{s}  \"message\": {f},\n", .{ item_indent, std.json.fmt(diagnostic.message, .{}) });
        try writer.print("{s}  \"sourcePath\": {f},\n", .{ item_indent, std.json.fmt(diagnostic.source_path, .{}) });
        if (diagnostic.span) |span| {
            try writer.print("{s}  \"span\": {{ \"start\": {d}, \"end\": {d} }},\n", .{ item_indent, span.start, span.end });
        } else {
            try writer.print("{s}  \"span\": null,\n", .{item_indent});
        }
        if (diagnostic.location) |location| {
            try writer.print("{s}  \"location\": {{ \"line\": {d}, \"column\": {d} }},\n", .{ item_indent, location.line, location.column });
        } else {
            try writer.print("{s}  \"location\": null,\n", .{item_indent});
        }
        try writer.print("{s}  \"fatal\": {any}\n", .{ item_indent, diagnostic.fatal });
        if (index + 1 < diagnostics.len) {
            try writer.print("{s}}},\n", .{item_indent});
        } else {
            try writer.print("{s}}}\n", .{item_indent});
        }
    }
}
