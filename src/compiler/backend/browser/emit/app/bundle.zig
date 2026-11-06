const std = @import("std");
const compiler_diagnostics = @import("../../../../diagnostics.zig");
const bundle_graph = @import("graph.zig");
const bundle_outputs = @import("bundle_outputs.zig");
const managed = @import("managed.zig");

pub const AppValidationReport = struct {
    diagnostics: []compiler_diagnostics.Diagnostic,

    pub fn deinit(self: *AppValidationReport, allocator: std.mem.Allocator) void {
        for (self.diagnostics) |*diagnostic| diagnostic.deinit(allocator);
        allocator.free(self.diagnostics);
        self.* = undefined;
    }
};

pub fn emitApp(root_component_path: []const u8, out_dir_path: []const u8, allocator: std.mem.Allocator) !void {
    return emitAppMode(root_component_path, out_dir_path, true, false, allocator);
}

pub fn emitAppLegacy(root_component_path: []const u8, out_dir_path: []const u8, allocator: std.mem.Allocator) !void {
    return emitAppMode(root_component_path, out_dir_path, false, false, allocator);
}

// Bundlers supply their reachable component roots and own one shared output graph.
// The manifest also redirects ordinary JS/TS consumers to the canonical modules.
pub fn emitManagedProject(manifest_path: []const u8, output_path: []const u8, json_diagnostics: bool, allocator: std.mem.Allocator) !void {
    const io = std.Io.Threaded.global_single_threaded.io();
    const input = try std.Io.Dir.cwd().readFileAlloc(io, manifest_path, allocator, .limited(4 * 1024 * 1024));
    defer allocator.free(input);
    const config = try std.json.parseFromSlice(struct { root: []const u8, components: []const []const u8 }, allocator, input, .{});
    defer config.deinit();
    var graph = bundle_graph.BundleGraph.init(config.value.root, allocator);
    defer graph.deinit();
    for (config.value.components) |source| {
        const canonical = try std.Io.Dir.cwd().realPathFileAlloc(io, source, allocator);
        defer allocator.free(canonical);
        _ = try graph.collect(canonical);
    }
    for (graph.nodes.items) |*node| {
        if (!std.mem.startsWith(u8, node.module_rel_path, "..")) continue;
        const safe = try std.fmt.allocPrint(allocator, "__weiv_components/{x}.mjs", .{std.hash.Wyhash.hash(0, node.abs_path)});
        allocator.free(node.module_rel_path);
        node.module_rel_path = safe;
    }
    var build = managed.Build.init(&graph, allocator);
    defer build.deinit();
    var out_dir = try std.Io.Dir.cwd().createDirPathOpen(io, output_path, .{});
    defer out_dir.close(io);
    build.prepare() catch |err| {
        if (build.warnings.hasFatal()) {
            try build.reportWarnings(json_diagnostics);
            return error.Reported;
        }
        return err;
    };
    build.writeComponents(out_dir) catch |err| {
        if (build.warnings.hasFatal()) {
            try build.reportWarnings(json_diagnostics);
            return error.Reported;
        }
        return err;
    };
    var entries = std.ArrayList(struct { source: []const u8, output: []const u8, component: bool }).empty;
    defer entries.deinit(allocator);
    for (graph.nodes.items) |node| try entries.append(allocator, .{ .source = node.abs_path, .output = node.module_rel_path, .component = true });
    var modules = build.modules.valueIterator();
    while (modules.next()) |module| try entries.append(allocator, .{ .source = module.*.path, .output = module.*.output, .component = false });
    const manifest = try std.json.Stringify.valueAlloc(allocator, .{ .modules = entries.items }, .{});
    defer allocator.free(manifest);
    try out_dir.writeFile(io, .{ .sub_path = "manifest.json", .data = manifest });
    try build.reportWarnings(json_diagnostics);
}

pub fn emitAppCells(root_component_path: []const u8, out_dir_path: []const u8, json_diagnostics: bool, allocator: std.mem.Allocator) !void {
    return emitAppMode(root_component_path, out_dir_path, true, json_diagnostics, allocator);
}

fn emitAppMode(root_component_path: []const u8, out_dir_path: []const u8, cells: bool, json_diagnostics: bool, allocator: std.mem.Allocator) !void {
    const root_abs_path = try std.Io.Dir.cwd().realPathFileAlloc(std.Io.Threaded.global_single_threaded.io(), root_component_path, allocator);
    defer allocator.free(root_abs_path);

    const root_dir = std.fs.path.dirname(root_abs_path) orelse return error.InvalidRootPath;
    var graph = bundle_graph.BundleGraph.init(root_dir, allocator);
    defer graph.deinit();

    const root_index = try graph.collect(root_abs_path);
    if (!cells) try graph.validateRuntimeImports();
    var managed_build = managed.Build.init(&graph, allocator);
    defer managed_build.deinit();
    if (cells) managed_build.prepare() catch |err| {
        if (managed_build.warnings.hasFatal()) {
            try managed_build.reportWarnings(json_diagnostics);
            return error.Reported;
        }
        return err;
    };

    var out_dir = try std.Io.Dir.cwd().createDirPathOpen(std.Io.Threaded.global_single_threaded.io(), out_dir_path, .{});
    defer out_dir.close(std.Io.Threaded.global_single_threaded.io());

    const styles_css = try graph.emitStylesheet(allocator);
    defer allocator.free(styles_css);
    try out_dir.writeFile(std.Io.Threaded.global_single_threaded.io(), .{ .sub_path = "styles.css", .data = styles_css });

    if (cells) managed_build.writeComponents(out_dir) catch |err| {
        if (managed_build.warnings.hasFatal()) {
            try managed_build.reportWarnings(json_diagnostics);
            return error.Reported;
        }
        return err;
    } else try graph.writeComponentModulesDirect(out_dir, allocator);

    const entry_source = try bundle_outputs.emitDirectEntry(&graph, root_index, allocator);
    defer allocator.free(entry_source);
    try out_dir.writeFile(std.Io.Threaded.global_single_threaded.io(), .{ .sub_path = "bundle.mjs", .data = entry_source });

    const browser_entry_source = try bundle_outputs.emitBrowserEntry(allocator);
    defer allocator.free(browser_entry_source);
    try out_dir.writeFile(std.Io.Threaded.global_single_threaded.io(), .{ .sub_path = "main.mjs", .data = browser_entry_source });

    const props_source = try bundle_outputs.emitPropsModule(&graph, root_index, allocator);
    defer allocator.free(props_source);
    try out_dir.writeFile(std.Io.Threaded.global_single_threaded.io(), .{ .sub_path = "props.mjs", .data = props_source });

    const html_source = try bundle_outputs.emitIndexHtml(&graph, root_index, allocator);
    defer allocator.free(html_source);
    try out_dir.writeFile(std.Io.Threaded.global_single_threaded.io(), .{ .sub_path = "index.html", .data = html_source });

    if (!cells) try graph.writeRuntimeImports(out_dir, allocator);

    const package_json = try bundle_outputs.emitPackageJson(allocator);
    defer allocator.free(package_json);
    try out_dir.writeFile(std.Io.Threaded.global_single_threaded.io(), .{ .sub_path = "package.json", .data = package_json });

    const dev_server = try bundle_outputs.emitDevServer(allocator);
    defer allocator.free(dev_server);
    try out_dir.writeFile(std.Io.Threaded.global_single_threaded.io(), .{ .sub_path = "server.ts", .data = dev_server });
    if (cells) try managed_build.reportWarnings(json_diagnostics);
}

pub fn validateApp(root_component_path: []const u8, allocator: std.mem.Allocator) !AppValidationReport {
    const root_abs_path = try std.Io.Dir.cwd().realPathFileAlloc(std.Io.Threaded.global_single_threaded.io(), root_component_path, allocator);
    defer allocator.free(root_abs_path);

    const root_dir = std.fs.path.dirname(root_abs_path) orelse return error.InvalidRootPath;
    var graph = bundle_graph.BundleGraph.init(root_dir, allocator);
    defer graph.deinit();

    var bag = compiler_diagnostics.DiagnosticBag.init();
    defer bag.deinit(allocator);

    try graph.collectValidated(root_abs_path, &bag);
    if (!bag.hasFatal()) {
        const graph_diagnostics = try graph.collectValidationDiagnostics(allocator);
        defer {
            for (graph_diagnostics) |*diagnostic| diagnostic.deinit(allocator);
            allocator.free(graph_diagnostics);
        }
        for (graph_diagnostics) |diagnostic| {
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

    const diagnostics = try bag.toOwnedSlice(allocator);
    return .{
        .diagnostics = diagnostics,
    };
}
