const std = @import("std");
const graph_module = @import("component_graph.zig");
const runtime = @import("runtime_imports.zig");
const backend = @import("../../../../../ffi/script_backend.zig");
const state = @import("../../../../project/state_dependencies.zig");
const ManagedPlan = @import("../../../../project/managed_state_plan.zig").ManagedPlan;
const diagnostics = @import("../../../../diagnostics.zig");
const browser_component = @import("../../component.zig");
const js_module = @import("../js_module.zig");
const js_output = @import("../js_module/output.zig");
fn io() std.Io {
    return std.Io.Threaded.global_single_threaded.io();
}

const Module = struct { path: []const u8, output: []const u8, publisher: []const u8, written: bool = false };
const Source = struct { source: []const u8, span_start: usize, span_end: usize, dynamic: bool = false };
const Sources = struct { ok: bool, sources: []const Source, opaque_dynamic_import: bool = false };
const ImportSites = struct {
    sources: []const Source = &.{},
    opaque_dynamic_imports: []const struct { span_start: usize, span_end: usize } = &.{},
};

// This owns actual emitted modules, not merely inspected source. Only selected
// declarations are lowered; every import of their canonical source uses one file.
pub const Build = struct {
    graph: *graph_module.ComponentGraph,
    allocator: std.mem.Allocator,
    plan: ManagedPlan = .{},
    warnings: diagnostics.DiagnosticBag = diagnostics.DiagnosticBag.init(),
    modules: std.StringHashMap(*Module),

    pub fn init(graph: *graph_module.ComponentGraph, allocator: std.mem.Allocator) Build {
        return .{ .graph = graph, .allocator = allocator, .modules = std.StringHashMap(*Module).init(allocator) };
    }

    pub fn deinit(self: *Build) void {
        var values = self.modules.valueIterator();
        while (values.next()) |item| {
            const owned = item.*;
            self.allocator.free(owned.path);
            self.allocator.free(owned.output);
            self.allocator.free(owned.publisher);
            self.allocator.destroy(owned);
        }
        self.modules.deinit();
        self.plan.deinit(self.allocator);
        self.warnings.deinit(self.allocator);
    }

    pub fn prepare(self: *Build) !void {
        for (self.graph.nodes.items) |*node| {
            try self.checkImportBoundary(.{ .text = node.model.sfc_document.script.content, .path = node.model.source_path, .document = node.model.source, .offset = node.model.sfc_document.script.content_span.start }, true);
            try self.rejectTemplateImports(&node.model);
            const entries = try state.analyzeManaged(&node.model, self.graph.root_dir, &self.plan, self.allocator);
            defer {
                for (entries) |*entry| entry.deinit(self.allocator);
                self.allocator.free(entries);
            }
            for (entries) |entry| try self.warnings.appendOwned(self.allocator, entry.code, entry.severity, entry.message, entry.stage, entry.source_path, entry.span, entry.location, entry.fatal);
        }
        for (self.plan.subscriptions.items) |subscription| _ = try self.module(subscription.module_path);
    }

    fn checkImportBoundary(self: *Build, source: @import("../cell_diagnostics.zig").ScriptSource, component: bool) !void {
        const raw = try backend.analyzeModuleStateRaw(source.text, source.path, self.allocator);
        defer self.allocator.free(raw);
        const facts = try std.json.parseFromSlice(ImportSites, self.allocator, raw, .{ .ignore_unknown_fields = true });
        defer facts.deinit();
        var rejected = false;
        for (facts.value.opaque_dynamic_imports) |site| {
            const span = diagnostics.Span{ .start = source.offset + site.span_start, .end = source.offset + site.span_end };
            try self.appendImportBoundary(source.path, source.document, span, component);
            rejected = true;
        }
        if (component) for (facts.value.sources) |site| {
            if (!site.dynamic) continue;
            try self.appendImportBoundary(source.path, source.document, .{ .start = source.offset + site.span_start, .end = source.offset + site.span_end }, true);
            rejected = true;
        };
        if (rejected) return error.OpaqueDynamicModuleImportUnsupported;
    }

    fn appendImportBoundary(self: *Build, path: []const u8, document: []const u8, span: diagnostics.Span, component: bool) !void {
        const message = if (component)
            "Component/template dynamic imports are outside experimental managed loading. Put a literal import() loader in a managed JS/TS module, or use an external observable/subscription adapter."
        else
            "Managed builds cannot resolve the target of this computed import. Use a literal module specifier or load outside the managed boundary and transfer updates through an observable/subscription adapter. (OpaqueDynamicModuleImportUnsupported)";
        try self.warnings.appendOwned(self.allocator, "reactivity.dynamic_module_import", .@"error", message, .emit, path, span, diagnostics.computeLocation(document, span), true);
    }

    fn rejectTemplateImports(self: *Build, model: *const @import("../../../../component_unit.zig").ComponentUnit) !void {
        const functions = @import("../../../../lower/template_functions.zig");
        var source = std.ArrayList(u8).empty;
        defer source.deinit(self.allocator);
        try source.appendSlice(self.allocator, "const __weiv_templates=[");
        const names = try functions.bindingNames(&model.script, self.allocator);
        defer self.allocator.free(names);
        var collector = functions.Collector{ .allocator = self.allocator, .script = &source, .template = model.sfc_document.template.content, .script_names = names, .include_pure = true };
        defer collector.locals.deinit(self.allocator);
        defer collector.records.deinit(self.allocator);
        collector.walk(model.normalized_template.nodes) catch |err| {
            if (err == error.OutOfMemory) return err;
            return; // Emission reports unsupported expression syntax at its source.
        };
        try source.appendSlice(self.allocator, "];");
        const raw = try backend.analyzeModuleStateRaw(source.items, "template.ts", self.allocator);
        defer self.allocator.free(raw);
        const facts = try std.json.parseFromSlice(ImportSites, self.allocator, raw, .{ .ignore_unknown_fields = true });
        defer facts.deinit();
        var sites = std.ArrayList(diagnostics.Span).empty;
        defer sites.deinit(self.allocator);
        for (facts.value.opaque_dynamic_imports) |site| try sites.append(self.allocator, .{ .start = site.span_start, .end = site.span_end });
        for (facts.value.sources) |site| if (site.dynamic) try sites.append(self.allocator, .{ .start = site.span_start, .end = site.span_end });
        var rejected = false;
        for (sites.items) |site| {
            for (collector.records.items) |record| {
                if (site.start < record.generated.start or site.end > record.generated.end) continue;
                const start = model.sfc_document.template.content_span.start + record.template.start + site.start - record.generated.start;
                try self.appendImportBoundary(model.source_path, model.source, .{ .start = start, .end = start + site.end - site.start }, true);
                rejected = true;
                break;
            }
        }
        if (rejected) return error.OpaqueDynamicModuleImportUnsupported;
    }

    pub fn reportWarnings(self: *Build, json: bool) !void {
        const entries = self.warnings.diagnostics.items;
        if (entries.len == 0) return;
        var output = std.Io.Writer.Allocating.init(self.allocator);
        defer output.deinit();
        if (json) {
            try output.writer.writeAll("{\"mode\":\"managed-project\",\"coverage\":\"managed-template-dependencies-and-assignment-sources\",\"diagnostics\":[\n");
            try diagnostics.writeJsonDiagnostics(&output.writer, entries, "  ");
            try output.writer.writeAll("]}\n");
        } else try diagnostics.writeTextDiagnostics(&output.writer, entries, "");
        try std.Io.File.stderr().writeStreamingAll(io(), output.written());
    }

    fn module(self: *Build, path: []const u8) !*Module {
        if (self.modules.get(path)) |existing| return existing;
        const output = try std.fmt.allocPrint(self.allocator, "__weiv_modules/{x}.mjs", .{std.hash.Wyhash.hash(0, path)});
        errdefer self.allocator.free(output);
        var existing = self.modules.valueIterator();
        while (existing.next()) |entry| if (std.mem.eql(u8, entry.*.output, output)) return error.ManagedModuleIdentityCollision;
        const publisher = try std.fmt.allocPrint(self.allocator, "{s}.publisher.mjs", .{output[0 .. output.len - 4]});
        errdefer self.allocator.free(publisher);
        const owned_path = try self.allocator.dupe(u8, path);
        errdefer self.allocator.free(owned_path);
        const created = try self.allocator.create(Module);
        errdefer self.allocator.destroy(created);
        created.* = .{ .path = owned_path, .output = output, .publisher = publisher };
        try self.modules.put(owned_path, created);
        return created;
    }

    fn resolve(self: *Build, importer: []const u8, specifier: []const u8) ![:0]u8 {
        const base = try std.fs.path.resolve(self.allocator, &.{ std.fs.path.dirname(importer) orelse ".", specifier });
        defer self.allocator.free(base);
        for ([_][]const u8{ "", ".ts", ".mts", ".js", ".mjs", "/index.ts", "/index.js" }) |suffix| {
            const candidate = try std.fmt.allocPrint(self.allocator, "{s}{s}", .{ base, suffix });
            defer self.allocator.free(candidate);
            const canonical = std.Io.Dir.cwd().realPathFileAlloc(io(), candidate, self.allocator) catch continue;
            errdefer self.allocator.free(canonical);
            const stat = std.Io.Dir.cwd().statFile(io(), canonical, .{}) catch {
                self.allocator.free(canonical);
                continue;
            };
            if (stat.kind != .file) {
                self.allocator.free(canonical);
                continue;
            }
            return canonical;
        }
        return error.ManagedModuleNotFound;
    }

    fn relative(self: *Build, from: []const u8, to: []const u8) ![]u8 {
        const from_abs = try std.fs.path.resolve(self.allocator, &.{ "/__weiv_output", std.fs.path.dirname(from) orelse "." });
        defer self.allocator.free(from_abs);
        const to_abs = try std.fs.path.resolve(self.allocator, &.{ "/__weiv_output", to });
        defer self.allocator.free(to_abs);
        const result = try std.fs.path.relative(self.allocator, "/", null, from_abs, to_abs);
        if (std.mem.startsWith(u8, result, ".")) return result;
        defer self.allocator.free(result);
        return std.fmt.allocPrint(self.allocator, "./{s}", .{result});
    }

    fn mapped(self: *Build, out_dir: std.Io.Dir, importer: []const u8, output: []const u8, specifier: []const u8, original: bool) anyerror![]u8 {
        if (runtime.isWeivRuntimeSpecifier(specifier)) return self.relative(output, runtime.runtimeOutputEntryForSpecifier(specifier));
        if (std.fs.path.isAbsolute(specifier)) {
            if (!original) return self.allocator.dupe(u8, specifier);
            return error.AbsoluteManagedImportUnsupported;
        }
        if (!std.mem.startsWith(u8, specifier, ".")) return std.fmt.allocPrint(self.allocator, "/__weiv_packages/{s}", .{specifier});
        if (!original) return self.allocator.dupe(u8, specifier);
        const path = try self.resolve(importer, specifier);
        defer self.allocator.free(path);
        if (std.mem.endsWith(u8, path, ".weiv")) {
            const index = self.graph.index_by_abs_path.get(path) orelse return error.UncollectedManagedComponent;
            return self.relative(output, self.graph.nodes.items[index].module_rel_path);
        }
        if (runtime.isJavaScriptModule(path) or runtime.isTranspilableTypeScriptModule(path)) {
            const dependency = try self.module(path);
            try self.writeModule(out_dir, dependency);
            return self.relative(output, dependency.output);
        }
        const asset = try std.fmt.allocPrint(self.allocator, "__weiv_assets/{x}{s}", .{ std.hash.Wyhash.hash(0, path), std.fs.path.extension(path) });
        defer self.allocator.free(asset);
        const data = try std.Io.Dir.cwd().readFileAlloc(io(), path, self.allocator, .limited(1024 * 1024));
        defer self.allocator.free(data);
        try self.write(out_dir, asset, data);
        return self.relative(output, asset);
    }

    // Literal spans come from the AST, so import-like strings/comments cannot
    // be mistaken for imports. This also handles multiline static re-exports.
    fn rewrite(self: *Build, out_dir: std.Io.Dir, source: []const u8, path: []const u8, output: []const u8, original: bool) ![]u8 {
        const json = try backend.analyzeModuleStateRaw(source, "generated.mjs", self.allocator);
        defer self.allocator.free(json);
        const facts = try std.json.parseFromSlice(Sources, self.allocator, json, .{ .ignore_unknown_fields = true });
        defer facts.deinit();
        if (!facts.value.ok) return error.ManagedImportAnalysisFailed;
        if (original and facts.value.opaque_dynamic_import) return error.OpaqueDynamicModuleImportUnsupported;
        var result = std.ArrayList(u8).empty;
        defer result.deinit(self.allocator);
        var previous: usize = 0;
        for (facts.value.sources) |item| {
            const target = try self.mapped(out_dir, path, output, item.source, original);
            defer self.allocator.free(target);
            try result.appendSlice(self.allocator, source[previous..item.span_start]);
            try js_output.emitString(target, &result, self.allocator);
            previous = item.span_end;
        }
        try result.appendSlice(self.allocator, source[previous..]);
        return result.toOwnedSlice(self.allocator);
    }

    fn write(self: *Build, out_dir: std.Io.Dir, path: []const u8, data: []const u8) !void {
        _ = self;
        if (std.fs.path.dirname(path)) |parent| try out_dir.createDirPath(io(), parent);
        try out_dir.writeFile(io(), .{ .sub_path = path, .data = data });
    }

    fn writeModule(self: *Build, out_dir: std.Io.Dir, item: *Module) anyerror!void {
        if (item.written) return;
        item.written = true; // Break import cycles while retaining one output identity.
        const source = try std.Io.Dir.cwd().readFileAlloc(io(), item.path, self.allocator, .limited(1024 * 1024));
        defer self.allocator.free(source);
        try self.checkImportBoundary(.{ .text = source, .path = item.path, .document = source }, false);
        const transpiled = try backend.transpileModule(source, item.path, self.allocator);
        defer self.allocator.free(transpiled);
        const rewritten = try self.rewrite(out_dir, transpiled, item.path, item.output, true);
        defer self.allocator.free(rewritten);
        var names = std.ArrayList([]const u8).empty;
        defer names.deinit(self.allocator);
        for (self.plan.subscriptions.items) |subscription| {
            if (!std.mem.eql(u8, subscription.module_path, item.path)) continue;
            var seen = false;
            for (names.items) |name| if (std.mem.eql(u8, name, subscription.name)) {
                seen = true;
            };
            if (!seen) try names.append(self.allocator, subscription.name);
        }
        if (names.items.len == 0) {
            const final = try self.rewrite(out_dir, rewritten, item.path, item.output, false);
            defer self.allocator.free(final);
            try self.write(out_dir, item.output, final);
            return;
        }
        var encoded = std.Io.Writer.Allocating.init(self.allocator);
        defer encoded.deinit();
        try encoded.writer.print("{f}", .{std.json.fmt(names.items, .{})});
        const companion = try self.relative(item.output, item.publisher);
        defer self.allocator.free(companion);
        const lowered = backend.lowerModuleCells(rewritten, "managed.mjs", companion, encoded.written(), self.allocator) catch |err| {
            // Diagnose original TS/JS, never offsets from transpiled/import-rewritten text.
            _ = try @import("../cell_diagnostics.zig").inspectScript(.{ .text = source, .path = item.path, .document = source }, encoded.written(), true, &self.warnings, self.allocator);
            return err;
        };
        defer self.allocator.free(lowered);
        const final = try self.rewrite(out_dir, lowered, item.path, item.output, false);
        defer self.allocator.free(final);
        try self.write(out_dir, item.output, final);
        const publisher = try self.rewrite(out_dir, "import {createModuleState} from 'weiv:cells'; export const moduleState=createModuleState();", item.path, item.publisher, false);
        defer self.allocator.free(publisher);
        try self.write(out_dir, item.publisher, publisher);
    }

    pub fn writeComponents(self: *Build, out_dir: std.Io.Dir) !void {
        for (self.graph.nodes.items) |*node| {
            var subscriptions = std.ArrayList(js_module.ManagedSubscription).empty;
            defer {
                for (subscriptions.items) |subscription| self.allocator.free(subscription.specifier);
                subscriptions.deinit(self.allocator);
            }
            for (self.plan.subscriptions.items) |subscription| {
                if (!std.mem.eql(u8, subscription.component_path, node.abs_path)) continue;
                if (!subscription.watch) continue;
                const item = try self.module(subscription.module_path);
                try self.writeModule(out_dir, item);
                const specifier = try self.relative(node.module_rel_path, item.publisher);
                try subscriptions.append(self.allocator, .{ .specifier = specifier, .name = subscription.name, .binding = subscription.binding });
            }
            var overrides = std.ArrayList(js_module.ImportOverride).empty;
            defer {
                for (overrides.items) |override| self.allocator.free(override.target);
                overrides.deinit(self.allocator);
            }
            for (node.model.script.imports) |record| {
                if (!runtime.shouldPreserveRuntimeImport(record, &node.model.script) and !std.mem.endsWith(u8, record.source, ".weiv")) continue;
                const target = try self.mapped(out_dir, node.abs_path, node.module_rel_path, record.source, true);
                try overrides.append(self.allocator, .{ .source = record.source, .target = target });
            }
            var browser = try browser_component.build(&node.model, self.allocator);
            defer browser.deinit(self.allocator);
            var local_names = std.ArrayList([]const u8).empty;
            defer local_names.deinit(self.allocator);
            for (self.plan.locals.items) |local| if (std.mem.eql(u8, local.component_path, node.abs_path)) try local_names.append(self.allocator, local.name);
            var local_subscriptions = std.ArrayList(js_module.LocalSubscription).empty;
            defer local_subscriptions.deinit(self.allocator);
            for (self.plan.local_subscriptions.items) |item| {
                if (std.mem.eql(u8, item.component_path, node.abs_path)) try local_subscriptions.append(self.allocator, .{ .name = item.name, .binding = item.binding, .publisher_backed = item.publisher_backed });
            }
            const generated = js_module.emitModuleWithSelection(&browser, subscriptions.items, overrides.items, local_names.items, local_subscriptions.items, self.allocator) catch |err| {
                try js_module.collectCellDiagnostics(&browser, local_names.items, &self.warnings, self.allocator);
                return err;
            };
            defer self.allocator.free(generated);
            const final = try self.rewrite(out_dir, generated, node.abs_path, node.module_rel_path, false);
            defer self.allocator.free(final);
            try self.write(out_dir, node.module_rel_path, final);
        }
        try self.graph.copyWeivRuntimeModule(out_dir, self.allocator);
        const cell = try runtime.runtimeSource("cell", self.allocator);
        defer self.allocator.free(cell);
        try self.graph.copyWeivRuntimeDependency(out_dir, cell, "__weiv_runtime/cell.js", self.allocator);
    }
};
