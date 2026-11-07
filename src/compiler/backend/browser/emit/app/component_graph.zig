const std = @import("std");
const compiler_compile = @import("../../../../compile.zig");
const compiler_diagnostics = @import("../../../../diagnostics.zig");
const component = @import("../../../../component_unit.zig");
const style = @import("../scoped_css.zig");
const runtime_imports = @import("runtime_imports.zig");

pub const ComponentGraph = struct {
    root_dir: []const u8,
    allocator: std.mem.Allocator,
    nodes: std.ArrayList(Node),
    index_by_abs_path: std.StringHashMap(usize),
    validation_seen_paths: std.StringHashMap(void),
    component_registry: std.StringHashMap(usize),
    copied_runtime_paths: std.StringHashMap(void),
    bare_imports: std.StringHashMap(void),

    pub fn init(root_dir: []const u8, allocator: std.mem.Allocator) ComponentGraph {
        return .{
            .root_dir = root_dir,
            .allocator = allocator,
            .nodes = std.ArrayList(Node).empty,
            .index_by_abs_path = std.StringHashMap(usize).init(allocator),
            .validation_seen_paths = std.StringHashMap(void).init(allocator),
            .component_registry = std.StringHashMap(usize).init(allocator),
            .copied_runtime_paths = std.StringHashMap(void).init(allocator),
            .bare_imports = std.StringHashMap(void).init(allocator),
        };
    }

    pub fn deinit(self: *ComponentGraph) void {
        for (self.nodes.items) |*node| node.deinit(self.allocator);
        self.nodes.deinit(self.allocator);
        self.index_by_abs_path.deinit();
        var validation_iter = self.validation_seen_paths.iterator();
        while (validation_iter.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
        }
        self.validation_seen_paths.deinit();
        var component_iter = self.component_registry.iterator();
        while (component_iter.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
        }
        self.component_registry.deinit();
        var copied_iter = self.copied_runtime_paths.iterator();
        while (copied_iter.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
        }
        self.copied_runtime_paths.deinit();
        var bare_iter = self.bare_imports.iterator();
        while (bare_iter.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
        }
        self.bare_imports.deinit();
    }

    pub fn collect(self: *ComponentGraph, abs_path: []const u8) !usize {
        if (self.index_by_abs_path.get(abs_path)) |existing| return existing;

        const source = try std.Io.Dir.cwd().readFileAlloc(std.Io.Threaded.global_single_threaded.io(), abs_path, self.allocator, .limited(1024 * 1024));
        errdefer self.allocator.free(source);

        const rel_source_path = try std.fs.path.relative(self.allocator, ".", null, self.root_dir, abs_path);
        errdefer self.allocator.free(rel_source_path);
        const module_rel_path = try replaceExtension(rel_source_path, ".mjs", self.allocator);
        errdefer self.allocator.free(module_rel_path);

        var model = try compiler_compile.compile(source, abs_path, self.allocator);
        errdefer model.deinit(self.allocator);

        const node_index = self.nodes.items.len;
        try self.nodes.append(self.allocator, .{
            .abs_path = try self.allocator.dupe(u8, abs_path),
            .source = source,
            .rel_source_path = rel_source_path,
            .module_rel_path = module_rel_path,
            .model = model,
        });
        try self.index_by_abs_path.put(self.nodes.items[node_index].abs_path, node_index);

        const component_dir = std.fs.path.dirname(abs_path) orelse return error.InvalidComponentPath;
        for (self.nodes.items[node_index].model.script.imports) |import_record| {
            if (!std.mem.endsWith(u8, import_record.source, ".weiv")) continue;
            if (import_record.local_name.len == 0) continue;

            const joined = try std.fs.path.resolve(self.allocator, &.{ component_dir, import_record.source });
            defer self.allocator.free(joined);

            const child_index = try self.collect(joined);
            try self.registerComponent(import_record.local_name, child_index);
        }

        return node_index;
    }

    pub fn collectValidated(
        self: *ComponentGraph,
        abs_path: []const u8,
        bag: *compiler_diagnostics.DiagnosticBag,
    ) !void {
        if (self.index_by_abs_path.get(abs_path) != null) return;
        if (self.validation_seen_paths.contains(abs_path)) return;
        try self.validation_seen_paths.put(try self.allocator.dupe(u8, abs_path), {});

        const source = try std.Io.Dir.cwd().readFileAlloc(std.Io.Threaded.global_single_threaded.io(), abs_path, self.allocator, .limited(1024 * 1024));
        errdefer self.allocator.free(source);

        var report = try compiler_compile.compileReport(source, abs_path, self.allocator);
        defer report.deinit(self.allocator);

        try appendDiagnosticsFromSlice(bag, report.diagnostics, self.allocator);
        if (compiler_diagnostics.hasFatalDiagnostics(report.diagnostics)) {
            self.allocator.free(source);
            return;
        }

        const rel_source_path = try std.fs.path.relative(self.allocator, ".", null, self.root_dir, abs_path);
        errdefer self.allocator.free(rel_source_path);
        const module_rel_path = try replaceExtension(rel_source_path, ".mjs", self.allocator);
        errdefer self.allocator.free(module_rel_path);

        var model = try report.takeUnit(self.allocator);
        errdefer model.deinit(self.allocator);

        const node_index = self.nodes.items.len;
        try self.nodes.append(self.allocator, .{
            .abs_path = try self.allocator.dupe(u8, abs_path),
            .source = source,
            .rel_source_path = rel_source_path,
            .module_rel_path = module_rel_path,
            .model = model,
        });
        try self.index_by_abs_path.put(self.nodes.items[node_index].abs_path, node_index);

        const component_dir = std.fs.path.dirname(abs_path) orelse return error.InvalidComponentPath;
        for (self.nodes.items[node_index].model.script.imports) |import_record| {
            if (!std.mem.endsWith(u8, import_record.source, ".weiv")) continue;
            if (import_record.local_name.len == 0) continue;

            const joined = try std.fs.path.resolve(self.allocator, &.{ component_dir, import_record.source });
            defer self.allocator.free(joined);

            try self.collectValidated(joined, bag);
            if (self.index_by_abs_path.get(joined)) |child_index| {
                try self.registerComponentValidated(
                    bag,
                    &self.nodes.items[node_index],
                    import_record.local_name,
                    import_record.span_start,
                    import_record.span_end,
                    child_index,
                );
            }
        }
    }

    pub fn emitStylesheet(self: *ComponentGraph, allocator: std.mem.Allocator) ![]u8 {
        var out = std.ArrayList(u8).empty;
        defer out.deinit(allocator);

        for (self.nodes.items, 0..) |*node, idx| {
            const css = try style.emitScopedCss(&node.model, allocator);
            defer allocator.free(css);
            if (css.len == 0) continue;
            if (out.items.len > 0 and idx > 0) {
                try out.appendSlice(allocator, "\n\n");
            }
            try out.appendSlice(allocator, css);
        }

        return try out.toOwnedSlice(allocator);
    }

    pub fn collectValidationDiagnostics(self: *ComponentGraph, allocator: std.mem.Allocator) ![]compiler_diagnostics.Diagnostic {
        var bag = compiler_diagnostics.DiagnosticBag.init();
        defer bag.deinit(allocator);

        for (self.nodes.items) |*node| {
            for (node.model.script.imports) |import_record| {
                if (!runtime_imports.shouldPreserveRuntimeImport(import_record, &node.model.script)) continue;

                const problem = runtime_imports.classifyRuntimeImportProblem(import_record.source) orelse continue;
                const span = compiler_diagnostics.Span{
                    .start = node.model.sfc_document.script.content_span.start + import_record.span_start,
                    .end = node.model.sfc_document.script.content_span.start + import_record.span_end,
                };

                try bag.appendOwned(
                    allocator,
                    problem.code,
                    .@"error",
                    problem.message,
                    .bundle,
                    node.abs_path,
                    span,
                    compiler_diagnostics.computeLocation(node.source, span),
                    true,
                );
            }

            try style.appendEmitDiagnostics(&bag, &node.model, node.source, allocator);
        }

        return bag.toOwnedSlice(allocator);
    }

    fn registerComponent(self: *ComponentGraph, tag_name: []const u8, node_index: usize) !void {
        if (self.component_registry.get(tag_name)) |existing| {
            if (existing != node_index) return error.ComponentTagConflict;
            return;
        }
        const owned_tag_name = try self.allocator.dupe(u8, tag_name);
        errdefer self.allocator.free(owned_tag_name);
        try self.component_registry.put(owned_tag_name, node_index);
    }

    fn registerComponentValidated(
        self: *ComponentGraph,
        bag: *compiler_diagnostics.DiagnosticBag,
        importer_node: *const Node,
        tag_name: []const u8,
        span_start: usize,
        span_end: usize,
        node_index: usize,
    ) !void {
        if (self.component_registry.get(tag_name)) |existing| {
            if (existing == node_index) return;

            const span = compiler_diagnostics.Span{
                .start = importer_node.model.sfc_document.script.content_span.start + span_start,
                .end = importer_node.model.sfc_document.script.content_span.start + span_end,
            };
            const message = try std.fmt.allocPrint(
                self.allocator,
                "Component tag `{s}` resolves to multiple .weiv files in the same app emit",
                .{tag_name},
            );
            defer self.allocator.free(message);

            try bag.appendOwned(
                self.allocator,
                "bundle.component_tag_conflict",
                .@"error",
                message,
                .bundle,
                importer_node.abs_path,
                span,
                compiler_diagnostics.computeLocation(importer_node.source, span),
                true,
            );
            return;
        }

        const owned_tag_name = try self.allocator.dupe(u8, tag_name);
        errdefer self.allocator.free(owned_tag_name);
        try self.component_registry.put(owned_tag_name, node_index);
    }

    pub fn copyWeivRuntimeModule(self: *ComponentGraph, out_dir: std.Io.Dir, allocator: std.mem.Allocator) !void {
        const runtime_abs_source = try runtime_imports.runtimeSource("index", allocator);
        defer allocator.free(runtime_abs_source);

        try self.copyWeivRuntimeDependency(out_dir, runtime_abs_source, runtime_imports.weiv_runtime_output_entry, allocator);
    }

    pub fn copyWeivRuntimeDependency(
        self: *ComponentGraph,
        out_dir: std.Io.Dir,
        abs_source: []const u8,
        output_rel_source: []const u8,
        allocator: std.mem.Allocator,
    ) !void {
        if (self.copied_runtime_paths.contains(output_rel_source)) return;

        const file_data = try std.Io.Dir.cwd().readFileAlloc(std.Io.Threaded.global_single_threaded.io(), abs_source, allocator, .limited(1024 * 1024));
        defer allocator.free(file_data);

        const module_output = try runtime_imports.emitRuntimeImportOutput(file_data, abs_source, output_rel_source, allocator);
        defer allocator.free(module_output);
        if (std.fs.path.dirname(output_rel_source)) |output_dirname| {
            if (!std.mem.eql(u8, output_dirname, ".") and output_dirname.len > 0) {
                try out_dir.createDirPath(std.Io.Threaded.global_single_threaded.io(), output_dirname);
            }
        }
        try out_dir.writeFile(std.Io.Threaded.global_single_threaded.io(), .{ .sub_path = output_rel_source, .data = module_output });
        try self.copied_runtime_paths.put(try self.allocator.dupe(u8, output_rel_source), {});

        const dependency_dir = std.fs.path.dirname(abs_source) orelse return;
        const nested_imports = try runtime_imports.parseJsModuleImports(file_data, allocator);
        defer {
            for (nested_imports) |item| allocator.free(item);
            allocator.free(nested_imports);
        }

        for (nested_imports) |nested_specifier| {
            if (!runtime_imports.isBrowserLoadableImport(nested_specifier) and !runtime_imports.isTranspilableTypeScriptModule(nested_specifier)) continue;
            const nested_abs_source = try std.fs.path.resolve(allocator, &.{ dependency_dir, nested_specifier });
            defer allocator.free(nested_abs_source);

            const nested_rewritten = try runtime_imports.emittedRuntimeImportPath(nested_specifier, allocator);
            defer allocator.free(nested_rewritten);

            const output_dir = std.fs.path.dirname(output_rel_source) orelse ".";
            const nested_output_rel_source = try std.fs.path.resolvePosix(allocator, &.{ output_dir, nested_rewritten });
            defer allocator.free(nested_output_rel_source);

            try self.copyWeivRuntimeDependency(out_dir, nested_abs_source, nested_output_rel_source, allocator);
        }
    }
};

const Node = struct {
    abs_path: []const u8,
    source: []const u8,
    rel_source_path: []const u8,
    module_rel_path: []const u8,
    model: component.ComponentUnit,

    fn deinit(self: *Node, allocator: std.mem.Allocator) void {
        allocator.free(self.abs_path);
        allocator.free(self.source);
        allocator.free(self.rel_source_path);
        allocator.free(self.module_rel_path);
        self.model.deinit(allocator);
    }
};

fn appendDiagnosticsFromSlice(
    bag: *compiler_diagnostics.DiagnosticBag,
    diagnostics: []const compiler_diagnostics.Diagnostic,
    allocator: std.mem.Allocator,
) !void {
    for (diagnostics) |diagnostic| {
        try bag.appendOwned(
            allocator,
            diagnostic.code,
            diagnostic.severity,
            diagnostic.message,
            diagnostic.stage,
            diagnostic.source_path,
            diagnostic.span,
            diagnostic.location,
            diagnostic.fatal,
        );
    }
}

fn replaceExtension(path: []const u8, new_extension: []const u8, allocator: std.mem.Allocator) ![]u8 {
    if (std.mem.endsWith(u8, path, ".weiv")) {
        return try std.fmt.allocPrint(allocator, "{s}{s}", .{ path[0 .. path.len - ".weiv".len], new_extension });
    }
    return try std.fmt.allocPrint(allocator, "{s}{s}", .{ path, new_extension });
}
