const std = @import("std");
const sir = @import("../../../../sema/sir.zig");
const script_backend = @import("../../../../../ffi/script_backend.zig");

pub var configured_runtime_dir: ?[]const u8 = null;

pub fn runtimeSource(name: []const u8, allocator: std.mem.Allocator) ![:0]u8 {
    const root = configured_runtime_dir orelse "packages/weiv/src/runtime";
    for ([_][]const u8{ ".ts", ".js" }) |extension| {
        const candidate = try std.fmt.allocPrint(allocator, "{s}/{s}{s}", .{ root, name, extension });
        defer allocator.free(candidate);
        const path = std.Io.Dir.cwd().realPathFileAlloc(std.Io.Threaded.global_single_threaded.io(), candidate, allocator) catch continue;
        return path;
    }
    return error.WeivRuntimeNotFound;
}

pub const weiv_runtime_legacy_package_specifier = "@weiv/runtime";
pub const weiv_virtual_observable_specifier = "weiv:observable";
pub const weiv_virtual_router_specifier = "weiv:router";
pub const weiv_virtual_cells_specifier = "weiv:cells";
pub const weiv_runtime_output_entry = "__weiv_runtime/index.js";
pub const weiv_runtime_observable_output_entry = "__weiv_runtime/observable.js";
pub const weiv_runtime_router_output_entry = "__weiv_runtime/router.js";

pub fn shouldCopyRuntimeImport(
    record: sir.ScriptImport,
    script: *const sir.ScriptFacts,
) bool {
    if (!shouldPreserveRuntimeImport(record, script)) return false;
    if (isWeivRuntimeSpecifier(record.source)) return true;
    return isBrowserLoadableImport(record.source) or isTranspilableTypeScriptModule(record.source);
}

pub fn shouldPreserveRuntimeImport(
    record: sir.ScriptImport,
    script: *const sir.ScriptFacts,
) bool {
    if (std.mem.endsWith(u8, record.source, ".weiv")) return false;
    if (std.mem.eql(u8, record.kind, "side_effect")) return true;

    for (script.bindings) |binding| {
        if (!std.mem.eql(u8, binding.name, record.local_name)) continue;
        return !std.mem.eql(u8, binding.kind, "type_only");
    }
    return true;
}

pub fn isBrowserLoadableImport(source: []const u8) bool {
    return std.mem.endsWith(u8, source, ".js") or
        std.mem.endsWith(u8, source, ".mjs") or
        std.mem.endsWith(u8, source, ".json") or
        std.mem.endsWith(u8, source, ".css");
}

pub fn isTranspilableTypeScriptModule(source: []const u8) bool {
    return std.mem.endsWith(u8, source, ".ts") or std.mem.endsWith(u8, source, ".mts");
}

pub fn isJavaScriptModule(path: []const u8) bool {
    return std.mem.endsWith(u8, path, ".js") or std.mem.endsWith(u8, path, ".mjs");
}

pub fn parseJsModuleImports(source: []const u8, allocator: std.mem.Allocator) ![][]u8 {
    var imports = std.ArrayList([]u8).empty;
    defer imports.deinit(allocator);

    var lines = std.mem.tokenizeScalar(u8, source, '\n');
    while (lines.next()) |line_raw| {
        const line = std.mem.trim(u8, line_raw, &std.ascii.whitespace);
        if (line.len == 0) continue;
        if (std.mem.startsWith(u8, line, "//")) continue;

        if (extractModuleSpecifier(line, "import ")) |specifier| {
            try imports.append(allocator, try allocator.dupe(u8, specifier));
            continue;
        }
        if (extractModuleSpecifier(line, "export ")) |specifier| {
            try imports.append(allocator, try allocator.dupe(u8, specifier));
            continue;
        }
    }

    return try imports.toOwnedSlice(allocator);
}

const RuntimeImportProblem = struct {
    code: []const u8,
    message: []const u8,
};

pub fn classifyRuntimeImportProblem(source_specifier: []const u8) ?RuntimeImportProblem {
    if (std.fs.path.isAbsolute(source_specifier)) {
        return .{
            .code = "import.unsupported_absolute_runtime_import",
            .message = "Absolute runtime imports are not supported in app emits",
        };
    }

    if (isWeivRuntimeSpecifier(source_specifier)) {
        return null;
    }

    const is_relative = std.mem.startsWith(u8, source_specifier, "./") or
        std.mem.startsWith(u8, source_specifier, "../");
    if (!is_relative) {
        return null;
    }

    if (!isBrowserLoadableImport(source_specifier) and !isTranspilableTypeScriptModule(source_specifier)) {
        return .{
            .code = "import.unsupported_runtime_import_type",
            .message = "Relative runtime imports must be browser-loadable modules or transpilable TypeScript modules",
        };
    }

    return null;
}

pub fn emittedRuntimeImportPath(source: []const u8, allocator: std.mem.Allocator) ![]u8 {
    if (std.mem.endsWith(u8, source, ".ts")) {
        return try std.fmt.allocPrint(allocator, "{s}.js", .{source[0 .. source.len - ".ts".len]});
    }
    if (std.mem.endsWith(u8, source, ".mts")) {
        return try std.fmt.allocPrint(allocator, "{s}.mjs", .{source[0 .. source.len - ".mts".len]});
    }
    return try allocator.dupe(u8, source);
}

pub fn emitRuntimeImportOutput(source: []const u8, source_path: []const u8, output_rel_path: []const u8, allocator: std.mem.Allocator) ![]u8 {
    if (isTranspilableTypeScriptModule(source_path)) {
        const transpiled = try script_backend.transpileModule(source, source_path, allocator);
        defer allocator.free(transpiled);
        return try rewriteRuntimeImportSpecifiers(transpiled, output_rel_path, allocator);
    }

    if (isJavaScriptModule(source_path)) {
        return try rewriteRuntimeImportSpecifiers(source, output_rel_path, allocator);
    }

    return try allocator.dupe(u8, source);
}

pub fn rewriteRuntimeImportSpecifiers(source: []const u8, output_rel_path: []const u8, allocator: std.mem.Allocator) ![]u8 {
    var out = std.ArrayList(u8).empty;
    defer out.deinit(allocator);

    var lines = std.mem.splitScalar(u8, source, '\n');
    var first = true;
    while (lines.next()) |line| {
        if (!first) try out.append(allocator, '\n');
        first = false;
        const rewritten = try rewriteImportLine(line, output_rel_path, allocator);
        defer allocator.free(rewritten);
        try out.appendSlice(allocator, rewritten);
    }

    return try out.toOwnedSlice(allocator);
}

fn rewriteImportLine(line: []const u8, output_rel_path: []const u8, allocator: std.mem.Allocator) ![]u8 {
    const trimmed = std.mem.trimStart(u8, line, &std.ascii.whitespace);
    const specifier = extractModuleSpecifier(trimmed, "import ") orelse extractModuleSpecifier(trimmed, "export ");
    if (specifier) |module_specifier| {
        if (isWeivRuntimeSpecifier(module_specifier)) {
            const rewritten_specifier = try relativeRuntimePackageSpecifier(module_specifier, output_rel_path, allocator);
            defer allocator.free(rewritten_specifier);
            return try replaceFirstSpecifier(line, module_specifier, rewritten_specifier, allocator);
        }
        if (isTranspilableTypeScriptModule(module_specifier)) {
            const rewritten_specifier = try emittedRuntimeImportPath(module_specifier, allocator);
            defer allocator.free(rewritten_specifier);
            return try replaceFirstSpecifier(line, module_specifier, rewritten_specifier, allocator);
        }
        if (isBareImportSpecifier(module_specifier)) {
            const rewritten_specifier = try std.fmt.allocPrint(allocator, "/__weiv_packages/{s}", .{module_specifier});
            defer allocator.free(rewritten_specifier);
            return try replaceFirstSpecifier(line, module_specifier, rewritten_specifier, allocator);
        }
    }
    return try allocator.dupe(u8, line);
}

fn isBareImportSpecifier(specifier: []const u8) bool {
    return !std.fs.path.isAbsolute(specifier) and
        !std.mem.startsWith(u8, specifier, "./") and
        !std.mem.startsWith(u8, specifier, "../") and
        !isWeivRuntimeSpecifier(specifier);
}

fn relativeRuntimePackageSpecifier(source_specifier: []const u8, output_rel_path: []const u8, allocator: std.mem.Allocator) ![]u8 {
    const output_dir = std.fs.path.dirname(output_rel_path) orelse ".";
    const runtime_output = runtimeOutputEntryForSpecifier(source_specifier);
    const relative = try relativeBundleSpecifier(output_dir, runtime_output, allocator);
    defer allocator.free(relative);
    if (std.mem.startsWith(u8, relative, "./") or std.mem.startsWith(u8, relative, "../")) {
        return try allocator.dupe(u8, relative);
    }
    return try std.fmt.allocPrint(allocator, "./{s}", .{relative});
}

fn relativeBundleSpecifier(from_dir: []const u8, to_path: []const u8, allocator: std.mem.Allocator) ![]u8 {
    if (from_dir.len == 0 or std.mem.eql(u8, from_dir, ".")) {
        return try allocator.dupe(u8, to_path);
    }

    var up_count: usize = 0;
    var components = std.mem.tokenizeScalar(u8, from_dir, '/');
    while (components.next()) |_| up_count += 1;

    var out = std.ArrayList(u8).empty;
    defer out.deinit(allocator);
    var i: usize = 0;
    while (i < up_count) : (i += 1) {
        try out.appendSlice(allocator, "../");
    }
    try out.appendSlice(allocator, to_path);
    return try out.toOwnedSlice(allocator);
}

pub fn isWeivRuntimeSpecifier(source_specifier: []const u8) bool {
    return std.mem.eql(u8, source_specifier, weiv_runtime_legacy_package_specifier) or
        std.mem.eql(u8, source_specifier, weiv_virtual_observable_specifier) or
        std.mem.eql(u8, source_specifier, weiv_virtual_cells_specifier) or
        std.mem.eql(u8, source_specifier, weiv_virtual_router_specifier);
}

pub fn runtimeOutputEntryForSpecifier(source_specifier: []const u8) []const u8 {
    if (std.mem.eql(u8, source_specifier, weiv_virtual_cells_specifier)) return "__weiv_runtime/cell.js";
    if (std.mem.eql(u8, source_specifier, weiv_virtual_observable_specifier)) {
        return weiv_runtime_observable_output_entry;
    }
    if (std.mem.eql(u8, source_specifier, weiv_virtual_router_specifier)) {
        return weiv_runtime_router_output_entry;
    }
    return weiv_runtime_output_entry;
}

fn replaceFirstSpecifier(line: []const u8, original: []const u8, replacement: []const u8, allocator: std.mem.Allocator) ![]u8 {
    const start = std.mem.indexOf(u8, line, original) orelse return allocator.dupe(u8, line);
    return try std.fmt.allocPrint(allocator, "{s}{s}{s}", .{
        line[0..start],
        replacement,
        line[start + original.len ..],
    });
}

fn extractModuleSpecifier(line: []const u8, prefix: []const u8) ?[]const u8 {
    if (!std.mem.startsWith(u8, line, prefix)) return null;

    if (std.mem.indexOf(u8, line, " from ")) |from_index| {
        return extractQuotedSpecifier(line[from_index + " from ".len ..]);
    }

    if (std.mem.startsWith(u8, line, "import ")) {
        return extractQuotedSpecifier(line["import ".len..]);
    }

    return null;
}

fn extractQuotedSpecifier(segment: []const u8) ?[]const u8 {
    const first_quote_index = std.mem.indexOfAny(u8, segment, "\"'") orelse return null;
    const quote = segment[first_quote_index];
    const rest = segment[first_quote_index + 1 ..];
    const end_index = std.mem.indexOfScalar(u8, rest, quote) orelse return null;
    return rest[0..end_index];
}
