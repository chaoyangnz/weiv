const std = @import("std");
const component = @import("../../../../component_unit.zig");
const sir = @import("../../../../sema/sir.zig");

pub fn shouldPreserveImport(record: sir.ScriptImport, script: *const sir.ScriptFacts) bool {
    if (std.mem.eql(u8, record.kind, "side_effect")) return true;
    for (script.bindings) |binding| {
        if (!std.mem.eql(u8, binding.name, record.local_name)) continue;
        return !std.mem.eql(u8, binding.kind, "type_only");
    }
    return true;
}

pub fn emittedRuntimeImportSpecifier(source: []const u8, allocator: std.mem.Allocator) ![]u8 {
    return rewriteModuleExtension(source, allocator);
}

pub fn emittedDirectImportSpecifier(source: []const u8, allocator: std.mem.Allocator) ![]u8 {
    if (std.mem.endsWith(u8, source, ".weiv")) {
        return try std.fmt.allocPrint(allocator, "{s}.mjs", .{source[0 .. source.len - ".weiv".len]});
    }
    return rewriteModuleExtension(source, allocator);
}

pub fn rewriteModuleExtension(source: []const u8, allocator: std.mem.Allocator) ![]u8 {
    if (std.mem.endsWith(u8, source, ".ts")) {
        return try std.fmt.allocPrint(allocator, "{s}.js", .{source[0 .. source.len - ".ts".len]});
    }
    if (std.mem.endsWith(u8, source, ".mts")) {
        return try std.fmt.allocPrint(allocator, "{s}.mjs", .{source[0 .. source.len - ".mts".len]});
    }
    return try allocator.dupe(u8, source);
}

pub fn buildPreservedImportsWithOverrides(model: *const component.ComponentUnit, overrides: []const @import("../js_module.zig").ImportOverride, allocator: std.mem.Allocator) ![]u8 {
    var out = std.ArrayList(u8).empty;
    defer out.deinit(allocator);

    for (model.script.imports) |record| {
        if (!shouldPreserveImport(record, &model.script)) continue;
        var target: ?[]const u8 = null;
        for (overrides) |override| if (std.mem.eql(u8, override.source, record.source)) {
            target = override.target;
            break;
        };
        if (std.mem.endsWith(u8, record.source, ".weiv")) {
            const spec = if (target) |value| try allocator.dupe(u8, value) else try emittedDirectImportSpecifier(record.source, allocator);
            defer allocator.free(spec);
            try out.print(allocator, "import * as {s} from \"{s}\";\n", .{ record.local_name, spec });
            continue;
        }
        const spec = if (target) |value| try allocator.dupe(u8, value) else try emittedRuntimeImportSpecifier(record.source, allocator);
        defer allocator.free(spec);
        if (std.mem.eql(u8, record.kind, "side_effect")) {
            try out.print(allocator, "import \"{s}\";\n", .{spec});
        } else if (std.mem.eql(u8, record.kind, "default")) {
            try out.print(allocator, "import __weiv_import_{s} from \"{s}\";\n", .{ record.local_name, spec });
        } else if (std.mem.eql(u8, record.kind, "namespace")) {
            try out.print(allocator, "import * as __weiv_import_{s} from \"{s}\";\n", .{ record.local_name, spec });
        } else if (std.mem.eql(u8, record.kind, "named")) {
            if (record.imported_name) |imported_name| {
                try out.print(allocator, "import {{ {s} as __weiv_import_{s} }} from \"{s}\";\n", .{ imported_name, record.local_name, spec });
            }
        }
    }

    if (out.items.len > 0) try out.appendSlice(allocator, "\n");
    return try out.toOwnedSlice(allocator);
}
