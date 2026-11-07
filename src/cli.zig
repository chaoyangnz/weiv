const state_dependencies = @import("compiler/project/state_dependencies.zig");
const std = @import("std");
const browser_backend = @import("compiler/backend/browser/index.zig");
const compiler_compile = @import("compiler/compile.zig");
const component = @import("compiler/component_unit.zig");
const compiler_diagnostics = @import("compiler/diagnostics.zig");
const inspect = @import("compiler/inspect/index.zig");
const parser = @import("compiler/parser/index.zig");
const script_backend = @import("ffi/script_backend.zig");

const app_emit = browser_backend.emit.app;
const browser_render_tree = browser_backend.render_tree;
const js_module = browser_backend.emit.js_module;
const invalidation_graph = inspect.invalidation_graph;
const style = browser_backend.emit.scoped_css;

const LoadedComponent = struct {
    source: []u8,
    model: component.ComponentUnit,

    fn deinit(self: *LoadedComponent, allocator: std.mem.Allocator) void {
        self.model.deinit(allocator);
        allocator.free(self.source);
    }
};

const WatchState = struct {
    stop: std.atomic.Value(bool) = std.atomic.Value(bool).init(false),
};

const DevWatcherContext = struct {
    root_path: []const u8,
    out_dir: []const u8,
    watch_root_dir: []const u8,
    ignore_dir: ?[]const u8,
    watch_poll_ms: u64,
    rebuild_debounce_ms: u64,
    state: *WatchState,
};

const dev_watch_poll_ms_default: u64 = 200;
const dev_rebuild_debounce_ms_default: u64 = 300;
var json_diagnostics_mode: bool = false;

pub const CliReportedError = error{Reported};

pub fn run(
    allocator: std.mem.Allocator,
    process_io: std.Io,
    process_args: std.process.Args,
    environ_map: *const std.process.Environ.Map,
) !void {
    var args = try std.process.Args.Iterator.initAllocator(process_args, allocator);
    defer args.deinit();

    _ = args.next();
    var command = args.next() orelse {
        try printUsage();
        return;
    };
    while (std.mem.eql(u8, command, "--json-diagnostics") or std.mem.eql(u8, command, "--runtime-dir")) {
        if (std.mem.eql(u8, command, "--json-diagnostics")) json_diagnostics_mode = true else {
            @import("compiler/backend/browser/emit/app/runtime_imports.zig").configured_runtime_dir = args.next() orelse return error.MissingRuntimeDirectory;
        }
        command = args.next() orelse {
            try printUsage();
            return;
        };
    }

    try rejectRetiredReactivityCommand(command);
    if (std.mem.eql(u8, command, "inspect")) {
        const subcommand = args.next() orelse {
            try printUsage();
            return;
        };
        if (std.mem.eql(u8, subcommand, "lir") or std.mem.eql(u8, subcommand, "ir")) {
            const path = args.next() orelse {
                try printUsage();
                return;
            };
            try runInspectLir(path, allocator);
            return;
        }
        if (std.mem.eql(u8, subcommand, "render-tree") or std.mem.eql(u8, subcommand, "browser-plan")) {
            const path = args.next() orelse {
                try printUsage();
                return;
            };
            try runInspectRenderTree(path, allocator);
            return;
        }
        if (std.mem.eql(u8, subcommand, "invalidation-graph")) {
            const path = args.next() orelse {
                try printUsage();
                return;
            };
            try runInspectInvalidationGraph(path, allocator);
            return;
        }
        try printUsage();
        return;
    }

    if (std.mem.eql(u8, command, "analyze")) {
        const phase = args.next() orelse {
            try printUsage();
            return;
        };
        try rejectRetiredReactivityCommand(phase);
        if (std.mem.eql(u8, phase, "state-boundaries")) {
            const path = args.next() orelse {
                try printUsage();
                return;
            };
            try runAnalyzeStateBoundaries(path, allocator);
            return;
        }
        if (std.mem.eql(u8, phase, "module-state")) {
            const path = args.next() orelse {
                try printUsage();
                return;
            };
            try runAnalyzeModuleState(path, allocator);
            return;
        }
        if (std.mem.eql(u8, phase, "script")) {
            const path = args.next() orelse {
                try printUsage();
                return;
            };
            try runAnalyzeScript(path, allocator);
            return;
        }
        if (std.mem.eql(u8, phase, "component")) {
            const path = args.next() orelse {
                try printUsage();
                return;
            };
            const json_flag = args.next();
            try runAnalyzeComponent(path, allocator, json_flag != null and std.mem.eql(u8, json_flag.?, "--json"));
            return;
        }
        try printUsage();
        return;
    }

    if (std.mem.eql(u8, command, "validate")) {
        const phase = args.next() orelse {
            try printUsage();
            return;
        };
        try rejectRetiredReactivityCommand(phase);
        if (std.mem.eql(u8, phase, "app")) {
            const root_path = args.next() orelse {
                try printUsage();
                return;
            };
            const json_flag = args.next();
            try runValidateApp(root_path, allocator, json_flag != null and std.mem.eql(u8, json_flag.?, "--json"));
            return;
        }
        try printUsage();
        return;
    }

    if (std.mem.eql(u8, command, "emit")) {
        const phase = args.next() orelse {
            try printUsage();
            return;
        };
        try rejectRetiredReactivityCommand(phase);
        if (std.mem.eql(u8, phase, "managed-project")) {
            const manifest = args.next() orelse return error.MissingModulePath;
            const output = args.next() orelse return error.MissingOutputDirectory;
            app_emit.emitManagedProject(manifest, output, json_diagnostics_mode, allocator) catch |err| {
                if (err == error.Reported) return err;
                try printCliStageError("emit managed-project", manifest, .bundle, "app.managed_emit_failed", err, allocator);
                return error.Reported;
            };
            return;
        }

        if (std.mem.eql(u8, phase, "module-cells")) {
            const path = args.next() orelse return error.MissingModulePath;
            const companion = args.next() orelse return error.MissingModuleCompanion;
            const bindings = args.next() orelse return error.MissingModuleBindings;
            const source = try std.Io.Dir.cwd().readFileAlloc(std.Io.Threaded.global_single_threaded.io(), path, allocator, .limited(1024 * 1024));
            defer allocator.free(source);
            const code = script_backend.lowerModuleCells(source, path, companion, bindings, allocator) catch |err| {
                var bag = compiler_diagnostics.DiagnosticBag.init();
                defer bag.deinit(allocator);
                if (try @import("compiler/backend/browser/emit/cell_diagnostics.zig").inspectScript(.{ .text = source, .path = path, .document = source }, bindings, true, &bag, allocator)) {
                    try printComponentDiagnosticsFailure("emit module-cells", path, bag.diagnostics.items);
                    return error.Reported;
                }
                try printCliStageError("emit module-cells", path, .emit, "emit.module_cells_unsupported", err, allocator);
                return error.Reported;
            };
            defer allocator.free(code);
            try writeOutput(null, code);
            return;
        }
        if (std.mem.eql(u8, phase, "ast")) {
            const path = args.next() orelse {
                try printUsage();
                return;
            };
            const out_path = args.next();
            try runEmitAst(path, out_path, allocator);
            return;
        }
        if (std.mem.eql(u8, phase, "sir")) {
            const path = args.next() orelse {
                try printUsage();
                return;
            };
            const out_path = args.next();
            try runEmitSir(path, out_path, allocator);
            return;
        }
        if (std.mem.eql(u8, phase, "lir")) {
            const path = args.next() orelse {
                try printUsage();
                return;
            };
            const out_path = args.next();
            try runEmitLir(path, out_path, allocator);
            return;
        }
        if (std.mem.eql(u8, phase, "render-tree") or std.mem.eql(u8, phase, "browser-plan")) {
            const path = args.next() orelse {
                try printUsage();
                return;
            };
            const out_path = args.next();
            try runEmitRenderTree(path, out_path, allocator);
            return;
        }
        if (std.mem.eql(u8, phase, "invalidation-graph")) {
            const path = args.next() orelse {
                try printUsage();
                return;
            };
            const out_path = args.next();
            try runEmitInvalidationGraph(path, out_path, allocator);
            return;
        }
        if (std.mem.eql(u8, phase, "js")) {
            const path = args.next() orelse {
                try printUsage();
                return;
            };
            const out_path = args.next();
            try runEmitJs(path, out_path, allocator);
            return;
        }
        if (std.mem.eql(u8, phase, "css")) {
            const path = args.next() orelse {
                try printUsage();
                return;
            };
            const out_path = args.next();
            try runEmitCss(path, out_path, allocator);
            return;
        }
        if (std.mem.eql(u8, phase, "app")) {
            const root_path = args.next() orelse {
                try printUsage();
                return;
            };
            const out_dir = args.next() orelse {
                try printUsage();
                return;
            };
            try runEmitApp(root_path, out_dir, allocator);
            return;
        }
        try printUsage();
        return;
    }

    if (std.mem.eql(u8, command, "compile")) {
        const maybe_subcommand = args.next() orelse {
            try printUsage();
            return;
        };

        if (std.mem.eql(u8, maybe_subcommand, "analyze")) {
            const phase = args.next() orelse {
                try printUsage();
                return;
            };
            try rejectRetiredReactivityCommand(phase);
            if (std.mem.eql(u8, phase, "script")) {
                const path = args.next() orelse {
                    try printUsage();
                    return;
                };
                try runAnalyzeScript(path, allocator);
                return;
            }
            if (std.mem.eql(u8, phase, "component")) {
                const path = args.next() orelse {
                    try printUsage();
                    return;
                };
                const json_flag = args.next();
                try runAnalyzeComponent(path, allocator, json_flag != null and std.mem.eql(u8, json_flag.?, "--json"));
                return;
            }
            try printUsage();
            return;
        }

        if (std.mem.eql(u8, maybe_subcommand, "validate")) {
            const phase = args.next() orelse {
                try printUsage();
                return;
            };
            try rejectRetiredReactivityCommand(phase);
            if (std.mem.eql(u8, phase, "app")) {
                const root_path = args.next() orelse {
                    try printUsage();
                    return;
                };
                const json_flag = args.next();
                try runValidateApp(root_path, allocator, json_flag != null and std.mem.eql(u8, json_flag.?, "--json"));
                return;
            }
            try printUsage();
            return;
        }

        if (std.mem.eql(u8, maybe_subcommand, "emit")) {
            const phase = args.next() orelse {
                try printUsage();
                return;
            };
            try rejectRetiredReactivityCommand(phase);
            if (std.mem.eql(u8, phase, "ast")) {
                const path = args.next() orelse {
                    try printUsage();
                    return;
                };
                const out_path = args.next();
                try runEmitAst(path, out_path, allocator);
                return;
            }
            if (std.mem.eql(u8, phase, "sir")) {
                const path = args.next() orelse {
                    try printUsage();
                    return;
                };
                const out_path = args.next();
                try runEmitSir(path, out_path, allocator);
                return;
            }
            if (std.mem.eql(u8, phase, "lir")) {
                const path = args.next() orelse {
                    try printUsage();
                    return;
                };
                const out_path = args.next();
                try runEmitLir(path, out_path, allocator);
                return;
            }
            if (std.mem.eql(u8, phase, "render-tree") or std.mem.eql(u8, phase, "browser-plan")) {
                const path = args.next() orelse {
                    try printUsage();
                    return;
                };
                const out_path = args.next();
                try runEmitRenderTree(path, out_path, allocator);
                return;
            }
            if (std.mem.eql(u8, phase, "invalidation-graph")) {
                const path = args.next() orelse {
                    try printUsage();
                    return;
                };
                const out_path = args.next();
                try runEmitInvalidationGraph(path, out_path, allocator);
                return;
            }
            if (std.mem.eql(u8, phase, "js")) {
                const path = args.next() orelse {
                    try printUsage();
                    return;
                };
                const out_path = args.next();
                try runEmitJs(path, out_path, allocator);
                return;
            }
            if (std.mem.eql(u8, phase, "css")) {
                const path = args.next() orelse {
                    try printUsage();
                    return;
                };
                const out_path = args.next();
                try runEmitCss(path, out_path, allocator);
                return;
            }

            if (std.mem.eql(u8, phase, "app")) {
                const root_path = args.next() orelse {
                    try printUsage();
                    return;
                };
                const out_dir = args.next() orelse {
                    try printUsage();
                    return;
                };
                try runEmitApp(root_path, out_dir, allocator);
                return;
            }
            try printUsage();
            return;
        }

        const root_path = maybe_subcommand;
        const out_dir = args.next() orelse "dist";
        try runEmitApp(root_path, out_dir, allocator);
        return;
    }

    if (std.mem.eql(u8, command, "analyze-script")) {
        const path = args.next() orelse {
            try printUsage();
            return;
        };
        try runAnalyzeScript(path, allocator);
        return;
    }

    if (std.mem.eql(u8, command, "analyze-component")) {
        const path = args.next() orelse {
            try printUsage();
            return;
        };
        const json_flag = args.next();
        try runAnalyzeComponent(path, allocator, json_flag != null and std.mem.eql(u8, json_flag.?, "--json"));
        return;
    }

    if (std.mem.eql(u8, command, "inspect-lir") or
        std.mem.eql(u8, command, "dump-lir") or
        std.mem.eql(u8, command, "inspect-ir") or
        std.mem.eql(u8, command, "dump-ir"))
    {
        const path = args.next() orelse {
            try printUsage();
            return;
        };
        try runInspectLir(path, allocator);
        return;
    }

    if (std.mem.eql(u8, command, "inspect-render-tree") or
        std.mem.eql(u8, command, "dump-render-tree") or
        std.mem.eql(u8, command, "inspect-browser-plan") or
        std.mem.eql(u8, command, "dump-browser-plan"))
    {
        const path = args.next() orelse {
            try printUsage();
            return;
        };
        try runInspectRenderTree(path, allocator);
        return;
    }

    if (std.mem.eql(u8, command, "inspect-invalidation-graph") or
        std.mem.eql(u8, command, "dump-invalidation-graph"))
    {
        const path = args.next() orelse {
            try printUsage();
            return;
        };
        try runInspectInvalidationGraph(path, allocator);
        return;
    }

    if (std.mem.eql(u8, command, "emit-js")) {
        const path = args.next() orelse {
            try printUsage();
            return;
        };
        const out_path = args.next();
        try runEmitJs(path, out_path, allocator);
        return;
    }

    if (std.mem.eql(u8, command, "emit-css")) {
        const path = args.next() orelse {
            try printUsage();
            return;
        };
        const out_path = args.next();
        try runEmitCss(path, out_path, allocator);
        return;
    }

    if (std.mem.eql(u8, command, "emit-app")) {
        const root_path = args.next() orelse {
            try printUsage();
            return;
        };
        const out_dir = args.next() orelse {
            try printUsage();
            return;
        };
        try runEmitApp(root_path, out_dir, allocator);
        return;
    }

    if (std.mem.eql(u8, command, "validate-app")) {
        const root_path = args.next() orelse {
            try printUsage();
            return;
        };
        const json_flag = args.next();
        try runValidateApp(root_path, allocator, json_flag != null and std.mem.eql(u8, json_flag.?, "--json"));
        return;
    }

    if (std.mem.eql(u8, command, "dev")) {
        const root_path = args.next() orelse {
            try printUsage();
            return;
        };
        const out_dir = args.next() orelse "dist";
        try runEmitApp(root_path, out_dir, allocator);
        try runDevServer(root_path, out_dir, allocator, process_io, environ_map);
        return;
    }

    try printUsage();
}

fn loadComponent(path: []const u8, allocator: std.mem.Allocator) !LoadedComponent {
    const source = std.Io.Dir.cwd().readFileAlloc(std.Io.Threaded.global_single_threaded.io(), path, allocator, .limited(1024 * 1024)) catch |err| {
        try printCliStageError("read component", path, .sfc_parse, "cli.read_failed", err, allocator);
        return error.Reported;
    };
    errdefer allocator.free(source);

    var report = compiler_compile.compileReport(source, path, allocator) catch |err| {
        try printCliStageError("compile component", path, .lowering, "component.compile_failed", err, allocator);
        return error.Reported;
    };
    defer report.deinit(allocator);

    if (hasFatalDiagnostics(report.diagnostics)) {
        try printComponentCompileFailure("compile component", path, report);
        return error.Reported;
    }

    var model = report.takeUnit(allocator) catch |err| {
        try printCliStageError("compile component", path, .lowering, "component.model_conversion_failed", err, allocator);
        return error.Reported;
    };
    errdefer model.deinit(allocator);

    return .{
        .source = source,
        .model = model,
    };
}

fn analyzeStateBoundaries(model: *const @import("compiler/component_unit.zig").ComponentUnit, allocator: std.mem.Allocator) ![]compiler_diagnostics.Diagnostic {
    return state_dependencies.analyze(model, allocator);
}

fn writeStateBoundaryReport(path: []const u8, entries: []const compiler_diagnostics.Diagnostic, allocator: std.mem.Allocator) ![]u8 {
    var out = std.Io.Writer.Allocating.init(allocator);
    defer out.deinit();
    try out.writer.print("{{\n  \"sourcePath\": {f},\n  \"mode\": \"state-boundaries\",\n  \"coverage\": \"initializers-helper-reads-and-assignment-sources\",\n  \"diagnostics\": [\n", .{std.json.fmt(path, .{})});
    try compiler_diagnostics.writeJsonDiagnostics(&out.writer, entries, "    ");
    try out.writer.writeAll("  ]\n}\n");
    return out.toOwnedSlice();
}

fn runAnalyzeStateBoundaries(path: []const u8, allocator: std.mem.Allocator) !void {
    var loaded = try loadComponent(path, allocator);
    defer loaded.deinit(allocator);
    const entries = try analyzeStateBoundaries(&loaded.model, allocator);
    defer {
        for (entries) |*entry| entry.deinit(allocator);
        allocator.free(entries);
    }
    const report = try writeStateBoundaryReport(path, entries, allocator);
    defer allocator.free(report);
    try std.Io.File.stdout().writeStreamingAll(std.Io.Threaded.global_single_threaded.io(), report);
}

fn printStateBoundaryWarnings(model: *const @import("compiler/component_unit.zig").ComponentUnit, allocator: std.mem.Allocator) !void {
    const entries = try analyzeStateBoundaries(model, allocator);
    defer {
        for (entries) |*entry| entry.deinit(allocator);
        allocator.free(entries);
    }
    if (entries.len == 0) return;
    const formatted = if (json_diagnostics_mode) try writeStateBoundaryReport(model.source_path, entries, allocator) else blk: {
        var out = std.Io.Writer.Allocating.init(allocator);
        defer out.deinit();
        try compiler_diagnostics.writeTextDiagnostics(&out.writer, entries, "");
        break :blk try out.toOwnedSlice();
    };
    defer allocator.free(formatted);
    try std.Io.File.stderr().writeStreamingAll(std.Io.Threaded.global_single_threaded.io(), formatted);
}

fn runAnalyzeModuleState(path: []const u8, allocator: std.mem.Allocator) !void {
    const source = std.Io.Dir.cwd().readFileAlloc(std.Io.Threaded.global_single_threaded.io(), path, allocator, .limited(1024 * 1024)) catch |err| {
        try printCliStageError("analyze module-state", path, .script_facts, "cli.read_failed", err, allocator);
        return error.Reported;
    };
    defer allocator.free(source);
    const analysis = try script_backend.analyzeModuleStateRaw(source, path, allocator);
    defer allocator.free(analysis);
    try std.Io.File.stdout().writeStreamingAll(std.Io.Threaded.global_single_threaded.io(), analysis);
    try std.Io.File.stdout().writeStreamingAll(std.Io.Threaded.global_single_threaded.io(), "\n");
}

fn runAnalyzeScript(path: []const u8, allocator: std.mem.Allocator) !void {
    const source = std.Io.Dir.cwd().readFileAlloc(std.Io.Threaded.global_single_threaded.io(), path, allocator, .limited(1024 * 1024)) catch |err| {
        try printCliStageError("analyze script", path, .script_facts, "cli.read_failed", err, allocator);
        return error.Reported;
    };
    defer allocator.free(source);

    const analysis_json = script_backend.analyzeScriptRaw(source, path, allocator) catch |err| {
        try printCliStageError("analyze script", path, .script_facts, "script.backend_failure", err, allocator);
        return error.Reported;
    };
    defer allocator.free(analysis_json);

    try std.Io.File.stdout().writeStreamingAll(std.Io.Threaded.global_single_threaded.io(), analysis_json);
    try std.Io.File.stdout().writeStreamingAll(std.Io.Threaded.global_single_threaded.io(), "\n");
}

fn runAnalyzeComponent(path: []const u8, allocator: std.mem.Allocator, json: bool) !void {
    const source = std.Io.Dir.cwd().readFileAlloc(std.Io.Threaded.global_single_threaded.io(), path, allocator, .limited(1024 * 1024)) catch |err| {
        try printCliStageError("read component", path, .sfc_parse, "cli.read_failed", err, allocator);
        return error.Reported;
    };
    defer allocator.free(source);

    var report = compiler_compile.compileReport(source, path, allocator) catch |err| {
        try printCliStageError("analyze component", path, .lowering, "component.compile_failed", err, allocator);
        return error.Reported;
    };
    defer report.deinit(allocator);
    if (json) {
        try printComponentAnalysisJson(report);
    } else {
        try printComponentAnalysisReport(report);
    }
}

fn runInspectLir(path: []const u8, allocator: std.mem.Allocator) !void {
    var loaded = try loadComponent(path, allocator);
    defer loaded.deinit(allocator);
    const formatted = try inspect.lir.formatDocument(loaded.model.lir_document, allocator);
    defer allocator.free(formatted);
    try std.Io.File.stdout().writeStreamingAll(std.Io.Threaded.global_single_threaded.io(), formatted);
}

fn runInspectRenderTree(path: []const u8, allocator: std.mem.Allocator) !void {
    var loaded = try loadComponent(path, allocator);
    defer loaded.deinit(allocator);

    var render_tree = browser_render_tree.lower(&loaded.model.lir_document, allocator) catch |err| {
        try printCliStageError("inspect render-tree", path, .render_tree, "render_tree.lower_failed", err, allocator);
        return error.Reported;
    };
    defer render_tree.deinit(allocator);

    const formatted = try inspect.render_tree.formatDocument(&render_tree, allocator);
    defer allocator.free(formatted);
    try std.Io.File.stdout().writeStreamingAll(std.Io.Threaded.global_single_threaded.io(), formatted);
}

fn runInspectInvalidationGraph(path: []const u8, allocator: std.mem.Allocator) !void {
    var loaded = try loadComponent(path, allocator);
    defer loaded.deinit(allocator);

    var render_tree = browser_render_tree.lower(&loaded.model.lir_document, allocator) catch |err| {
        try printCliStageError("inspect invalidation-graph", path, .render_tree, "render_tree.lower_failed", err, allocator);
        return error.Reported;
    };
    defer render_tree.deinit(allocator);

    const formatted = invalidation_graph.formatDocument(&loaded.model, &render_tree, allocator) catch |err| {
        try printCliStageError("inspect invalidation-graph", path, .lowering, "invalidation_graph.format_failed", err, allocator);
        return error.Reported;
    };
    defer allocator.free(formatted);
    try std.Io.File.stdout().writeStreamingAll(std.Io.Threaded.global_single_threaded.io(), formatted);
}

fn runEmitAst(path: []const u8, out_path: ?[]const u8, allocator: std.mem.Allocator) !void {
    const source = std.Io.Dir.cwd().readFileAlloc(std.Io.Threaded.global_single_threaded.io(), path, allocator, .limited(1024 * 1024)) catch |err| {
        try printCliStageError("emit ast", path, .sfc_parse, "cli.read_failed", err, allocator);
        return error.Reported;
    };
    defer allocator.free(source);

    const formatted = inspect.ast.formatSource(source, path, allocator) catch |err| {
        try printCliStageError("emit ast", path, .template_parse, "ast.emit_failed", err, allocator);
        return error.Reported;
    };
    defer allocator.free(formatted);
    try writeOutput(out_path, formatted);
}

fn runEmitSir(path: []const u8, out_path: ?[]const u8, allocator: std.mem.Allocator) !void {
    const source = std.Io.Dir.cwd().readFileAlloc(std.Io.Threaded.global_single_threaded.io(), path, allocator, .limited(1024 * 1024)) catch |err| {
        try printCliStageError("emit sir", path, .sfc_parse, "cli.read_failed", err, allocator);
        return error.Reported;
    };
    defer allocator.free(source);

    var report = compiler_compile.compileReport(source, path, allocator) catch |err| {
        try printCliStageError("emit sir", path, .binding, "component.compile_failed", err, allocator);
        return error.Reported;
    };
    defer report.deinit(allocator);

    if (report.script == null or report.template_bindings == null) {
        try printComponentCompileFailure("emit sir", path, report);
        return error.Reported;
    }

    const script = if (report.script) |*value| value else unreachable;
    const template_bindings = if (report.template_bindings) |*value| value else unreachable;
    const formatted = try inspect.sir.formatData(path, script, template_bindings, allocator);
    defer allocator.free(formatted);
    try writeOutput(out_path, formatted);
}

fn runEmitLir(path: []const u8, out_path: ?[]const u8, allocator: std.mem.Allocator) !void {
    var loaded = try loadComponent(path, allocator);
    defer loaded.deinit(allocator);

    const formatted = try inspect.lir.formatDocument(loaded.model.lir_document, allocator);
    defer allocator.free(formatted);
    try writeOutput(out_path, formatted);
}

fn runEmitRenderTree(path: []const u8, out_path: ?[]const u8, allocator: std.mem.Allocator) !void {
    var loaded = try loadComponent(path, allocator);
    defer loaded.deinit(allocator);

    var render_tree = browser_render_tree.lower(&loaded.model.lir_document, allocator) catch |err| {
        try printCliStageError("emit render-tree", path, .render_tree, "render_tree.lower_failed", err, allocator);
        return error.Reported;
    };
    defer render_tree.deinit(allocator);

    const formatted = try inspect.render_tree.formatDocument(&render_tree, allocator);
    defer allocator.free(formatted);
    try writeOutput(out_path, formatted);
}

fn runEmitInvalidationGraph(path: []const u8, out_path: ?[]const u8, allocator: std.mem.Allocator) !void {
    var loaded = try loadComponent(path, allocator);
    defer loaded.deinit(allocator);

    var render_tree = browser_render_tree.lower(&loaded.model.lir_document, allocator) catch |err| {
        try printCliStageError("emit invalidation-graph", path, .render_tree, "render_tree.lower_failed", err, allocator);
        return error.Reported;
    };
    defer render_tree.deinit(allocator);

    const formatted = invalidation_graph.formatDocument(&loaded.model, &render_tree, allocator) catch |err| {
        try printCliStageError("emit invalidation-graph", path, .lowering, "invalidation_graph.format_failed", err, allocator);
        return error.Reported;
    };
    defer allocator.free(formatted);
    try writeOutput(out_path, formatted);
}

fn writeOutput(path: ?[]const u8, data: []const u8) !void {
    const output_path = path orelse {
        try std.Io.File.stdout().writeStreamingAll(std.Io.Threaded.global_single_threaded.io(), data);
        return;
    };
    try writeOutputFile(output_path, data);
}

fn writeOutputFile(path: []const u8, data: []const u8) !void {
    if (std.fs.path.dirname(path)) |dirname| {
        if (dirname.len > 0 and !std.mem.eql(u8, dirname, ".")) {
            try std.Io.Dir.cwd().createDirPath(std.Io.Threaded.global_single_threaded.io(), dirname);
        }
    }
    try std.Io.Dir.cwd().writeFile(std.Io.Threaded.global_single_threaded.io(), .{ .sub_path = path, .data = data });
}

fn runEmitJs(path: []const u8, out_path: ?[]const u8, allocator: std.mem.Allocator) !void {
    var loaded = try loadComponent(path, allocator);
    defer loaded.deinit(allocator);

    if (try printStyleEmitDiagnostics("emit js", path, &loaded, allocator)) {
        return error.Reported;
    }

    var browser_component_model = browser_backend.component.build(&loaded.model, allocator) catch |err| {
        try printCliStageError("emit js", path, .render_tree, "browser_component.build_failed", err, allocator);
        return error.Reported;
    };
    defer browser_component_model.deinit(allocator);

    const js = js_module.emitModule(&browser_component_model, allocator) catch |err| {
        {
            var bag = compiler_diagnostics.DiagnosticBag.init();
            defer bag.deinit(allocator);
            try js_module.collectCellDiagnostics(&browser_component_model, null, &bag, allocator);
            if (bag.hasFatal()) {
                try printComponentDiagnosticsFailure("emit js", path, bag.diagnostics.items);
                return error.Reported;
            }
        }
        try printCliStageError("emit js", path, .emit, "emit.js_failed", err, allocator);
        return error.Reported;
    };
    defer allocator.free(js);
    try printStateBoundaryWarnings(&loaded.model, allocator);
    try writeOutput(out_path, js);
}

fn runEmitCss(path: []const u8, out_path: ?[]const u8, allocator: std.mem.Allocator) !void {
    var loaded = try loadComponent(path, allocator);
    defer loaded.deinit(allocator);

    if (try printStyleEmitDiagnostics("emit css", path, &loaded, allocator)) {
        return error.Reported;
    }

    const css = style.emitScopedCss(&loaded.model, allocator) catch |err| {
        try printCliStageError("emit css", path, .emit, "emit.css_failed", err, allocator);
        return error.Reported;
    };
    defer allocator.free(css);
    try writeOutput(out_path, css);
}

fn runEmitApp(root_path: []const u8, out_dir: []const u8, allocator: std.mem.Allocator) !void {
    var validation = app_emit.validateApp(root_path, allocator) catch |err| {
        try printCliStageError("validate app", root_path, .bundle, "app.validate_failed", err, allocator);
        return error.Reported;
    };
    defer validation.deinit(allocator);

    if (hasFatalDiagnostics(validation.diagnostics)) {
        try printAppValidationDiagnostics(root_path, validation.diagnostics);
        return error.Reported;
    }

    app_emit.emitAppWithDiagnostics(root_path, out_dir, json_diagnostics_mode, allocator) catch |err| {
        if (err == error.Reported) return err;
        try printCliStageError("emit app", root_path, .bundle, "app.emit_failed", err, allocator);
        return error.Reported;
    };
}

fn runValidateApp(root_path: []const u8, allocator: std.mem.Allocator, json: bool) !void {
    var validation = app_emit.validateApp(root_path, allocator) catch |err| {
        try printCliStageError("validate app", root_path, .bundle, "app.validate_failed", err, allocator);
        return error.Reported;
    };
    defer validation.deinit(allocator);

    if (json) {
        const formatted = try formatAppValidationDiagnosticsJson(root_path, validation.diagnostics, allocator);
        defer allocator.free(formatted);
        try std.Io.File.stdout().writeStreamingAll(std.Io.Threaded.global_single_threaded.io(), formatted);
    } else if (validation.diagnostics.len == 0) {
        try std.Io.File.stdout().writeStreamingAll(std.Io.Threaded.global_single_threaded.io(), "app validation ok\n");
    } else {
        try printAppValidationDiagnostics(root_path, validation.diagnostics);
    }

    if (hasFatalDiagnostics(validation.diagnostics)) {
        return error.Reported;
    }
}

fn printUsage() !void {
    try std.Io.File.stderr().writeStreamingAll(std.Io.Threaded.global_single_threaded.io(),
        \\Usage:
        \\  weiv --json-diagnostics <command...>
        \\  weiv analyze script <path>
        \\  weiv analyze component <path> [--json]
        \\  weiv validate app <root.weiv> [--json]
        \\  weiv emit ast <path> [out-file]
        \\  weiv emit sir <path> [out-file]
        \\  weiv emit lir <path> [out-file]
        \\  weiv emit render-tree <path> [out-file]
        \\  weiv emit invalidation-graph <path> [out-file]
        \\  weiv emit js <path> [out-file]
        \\  weiv emit managed-project <manifest.json> <out-dir>  (bundler integration)
        \\  weiv --runtime-dir <directory> <command>  (packaged runtime location)
        \\  weiv emit css <path> [out-file]
        \\  weiv compile <root.weiv> [out-dir]
        \\  weiv dev <root.weiv> [out-dir]
        \\
        \\Compatibility / internal:
        \\  weiv compile analyze script <path>
        \\  weiv compile analyze component <path>
        \\  weiv compile validate app <root.weiv> [--json]
        \\  weiv compile emit ast <path> [out-file]
        \\  weiv compile emit sir <path> [out-file]
        \\  weiv compile emit lir <path> [out-file]
        \\  weiv compile emit render-tree <path> [out-file]
        \\  weiv compile emit invalidation-graph <path> [out-file]
        \\  weiv compile emit js <path> [out-file]
        \\  weiv compile emit css <path> [out-file]
        \\  weiv compile emit app <root.weiv> <out-dir>
        \\  weiv analyze-script <path>
        \\  weiv analyze-component <path>
        \\  weiv analyze state-boundaries <path> (dependency diagnostics)
        \\  weiv analyze module-state <path>     (module provenance facts)
        \\  weiv emit module-cells <path> <companion-import> <bindings-json>  (internal prototype)
        \\  weiv emit-js <path> [out-file]
        \\  weiv emit-css <path> [out-file]
        \\  weiv emit-app <root.weiv> <out-dir>
        \\  weiv validate-app <root.weiv> [--json]
        \\
    );
}

fn friendlyErrorName(err: anyerror) []const u8 {
    return @errorName(err);
}

pub fn printUnhandledError(err: anyerror) !void {
    try printCliStageError("run", "<process>", .bundle, "cli.unhandled_error", err, std.heap.page_allocator);
}

fn printCliStageError(
    action: []const u8,
    source_path: []const u8,
    stage: compiler_diagnostics.Stage,
    code: []const u8,
    err: anyerror,
    allocator: std.mem.Allocator,
) !void {
    var bag = compiler_diagnostics.DiagnosticBag.init();
    defer bag.deinit(allocator);

    const message = try std.fmt.allocPrint(allocator, "{s} ({s})", .{ action, friendlyErrorName(err) });
    defer allocator.free(message);

    try bag.appendOwned(
        allocator,
        code,
        .@"error",
        message,
        stage,
        source_path,
        null,
        null,
        true,
    );

    const diagnostics = try bag.toOwnedSlice(allocator);
    defer {
        for (diagnostics) |*diagnostic| diagnostic.deinit(allocator);
        allocator.free(diagnostics);
    }
    try printComponentDiagnosticsFailure(action, source_path, diagnostics);
}

fn printComponentCompileFailure(action: []const u8, path: []const u8, report: component.ComponentCompileReport) !void {
    if (json_diagnostics_mode) {
        var stderr = std.Io.File.stderr();
        const formatted = try formatComponentCompileReportJson(report, std.heap.page_allocator);
        defer std.heap.page_allocator.free(formatted);
        try stderr.writeStreamingAll(std.Io.Threaded.global_single_threaded.io(), formatted);
        return;
    }

    var stderr = std.Io.File.stderr();
    var buffer: [1024]u8 = undefined;
    var writer = stderr.writer(std.Io.Threaded.global_single_threaded.io(), &buffer);
    const formatted = try formatComponentCompileReport(report, std.heap.page_allocator);
    defer std.heap.page_allocator.free(formatted);
    try writer.interface.print("weiv {s} failed for {s}\n", .{ action, path });
    try writer.interface.flush();
    try stderr.writeStreamingAll(std.Io.Threaded.global_single_threaded.io(), formatted);
}

fn printComponentDiagnosticsFailure(
    action: []const u8,
    path: []const u8,
    diagnostics: []const compiler_diagnostics.Diagnostic,
) !void {
    if (json_diagnostics_mode) {
        var stderr = std.Io.File.stderr();
        const formatted = try formatFailureDiagnosticsJson(action, path, diagnostics, std.heap.page_allocator);
        defer std.heap.page_allocator.free(formatted);
        try stderr.writeStreamingAll(std.Io.Threaded.global_single_threaded.io(), formatted);
        return;
    }

    var stderr = std.Io.File.stderr();
    var buffer: [1024]u8 = undefined;
    var writer = stderr.writer(std.Io.Threaded.global_single_threaded.io(), &buffer);
    try writer.interface.print("weiv {s} failed for {s}\n", .{ action, path });
    try writer.interface.flush();

    var out = std.Io.Writer.Allocating.init(std.heap.page_allocator);
    defer out.deinit();
    const out_writer = &out.writer;
    try compiler_diagnostics.writeTextDiagnostics(out_writer, diagnostics, "  ");
    const formatted = try out.toOwnedSlice();
    defer std.heap.page_allocator.free(formatted);
    try stderr.writeStreamingAll(std.Io.Threaded.global_single_threaded.io(), formatted);
}

fn printStyleEmitDiagnostics(
    action: []const u8,
    path: []const u8,
    loaded: *const LoadedComponent,
    allocator: std.mem.Allocator,
) !bool {
    var bag = compiler_diagnostics.DiagnosticBag.init();
    defer bag.deinit(allocator);
    try style.appendEmitDiagnostics(&bag, &loaded.model, loaded.source, allocator);
    if (!bag.hasFatal()) return false;
    const diagnostics = try bag.toOwnedSlice(allocator);
    defer {
        for (diagnostics) |*diagnostic| diagnostic.deinit(allocator);
        allocator.free(diagnostics);
    }
    try printComponentDiagnosticsFailure(action, path, diagnostics);
    return true;
}

fn hasFatalDiagnostics(diagnostics: []const compiler_diagnostics.Diagnostic) bool {
    return compiler_diagnostics.hasFatalDiagnostics(diagnostics);
}

pub fn formatAppValidationDiagnostics(
    root_path: []const u8,
    diagnostics: []const compiler_diagnostics.Diagnostic,
    allocator: std.mem.Allocator,
) ![]u8 {
    var out = std.Io.Writer.Allocating.init(allocator);
    defer out.deinit();
    const writer = &out.writer;

    try writer.print("weiv validate app failed for {s}\n", .{root_path});
    try compiler_diagnostics.writeTextDiagnostics(writer, diagnostics, "  ");

    return out.toOwnedSlice();
}

pub fn formatAppValidationDiagnosticsJson(
    root_path: []const u8,
    diagnostics: []const compiler_diagnostics.Diagnostic,
    allocator: std.mem.Allocator,
) ![]u8 {
    var out = std.Io.Writer.Allocating.init(allocator);
    defer out.deinit();
    const writer = &out.writer;

    try writer.writeAll("{\n");
    try writer.print("  \"rootPath\": {f},\n", .{std.json.fmt(root_path, .{})});
    try writer.print("  \"ok\": {any},\n", .{!hasFatalDiagnostics(diagnostics)});
    try writer.writeAll("  \"diagnostics\": [\n");
    try compiler_diagnostics.writeJsonDiagnostics(writer, diagnostics, "    ");
    try writer.writeAll("  ]\n");
    try writer.writeAll("}\n");
    return out.toOwnedSlice();
}

fn printAppValidationDiagnostics(root_path: []const u8, diagnostics: []const compiler_diagnostics.Diagnostic) !void {
    if (json_diagnostics_mode) {
        var stderr = std.Io.File.stderr();
        const formatted = try formatAppValidationDiagnosticsJson(root_path, diagnostics, std.heap.page_allocator);
        defer std.heap.page_allocator.free(formatted);
        try stderr.writeStreamingAll(std.Io.Threaded.global_single_threaded.io(), formatted);
        return;
    }

    var stderr = std.Io.File.stderr();
    const formatted = try formatAppValidationDiagnostics(root_path, diagnostics, std.heap.page_allocator);
    defer std.heap.page_allocator.free(formatted);
    try stderr.writeStreamingAll(std.Io.Threaded.global_single_threaded.io(), formatted);
}

fn formatFailureDiagnosticsJson(
    action: []const u8,
    source_path: []const u8,
    diagnostics: []const compiler_diagnostics.Diagnostic,
    allocator: std.mem.Allocator,
) ![]u8 {
    var out = std.Io.Writer.Allocating.init(allocator);
    defer out.deinit();
    const writer = &out.writer;

    try writer.writeAll("{\n");
    try writer.print("  \"action\": {f},\n", .{std.json.fmt(action, .{})});
    try writer.print("  \"sourcePath\": {f},\n", .{std.json.fmt(source_path, .{})});
    try writer.print("  \"ok\": {any},\n", .{!hasFatalDiagnostics(diagnostics)});
    try writer.writeAll("  \"diagnostics\": [\n");
    try compiler_diagnostics.writeJsonDiagnostics(writer, diagnostics, "    ");
    try writer.writeAll("  ]\n");
    try writer.writeAll("}\n");
    return out.toOwnedSlice();
}

pub fn formatCliFailureDiagnosticsJson(
    action: []const u8,
    source_path: []const u8,
    diagnostics: []const compiler_diagnostics.Diagnostic,
    allocator: std.mem.Allocator,
) ![]u8 {
    return formatFailureDiagnosticsJson(action, source_path, diagnostics, allocator);
}

fn runDevServer(
    root_path: []const u8,
    out_dir: []const u8,
    allocator: std.mem.Allocator,
    process_io: std.Io,
    parent_environ_map: *const std.process.Environ.Map,
) !void {
    printDevInfo("session.start", "root={s} out={s}", .{ root_path, out_dir });
    printDevInfo("watch.starting", "starting watch/rebuild loop", .{});

    const root_abs_path = try std.Io.Dir.cwd().realPathFileAlloc(std.Io.Threaded.global_single_threaded.io(), root_path, allocator);
    defer allocator.free(root_abs_path);
    const watch_root_dir = std.fs.path.dirname(root_abs_path) orelse return error.InvalidRootPath;

    const out_abs_path = try std.Io.Dir.cwd().realPathFileAlloc(std.Io.Threaded.global_single_threaded.io(), out_dir, allocator);
    defer allocator.free(out_abs_path);

    const ignore_dir = if (std.mem.startsWith(u8, out_abs_path, watch_root_dir) and
        (out_abs_path.len == watch_root_dir.len or out_abs_path[watch_root_dir.len] == std.fs.path.sep))
        try allocator.dupe(u8, out_abs_path)
    else
        null;
    defer if (ignore_dir) |value| allocator.free(value);

    var watch_state = WatchState{};
    const watch_poll_ms = readDevTimingEnvU64("WEIV_DEV_WATCH_POLL_MS", dev_watch_poll_ms_default);
    const rebuild_debounce_ms = readDevTimingEnvU64("WEIV_DEV_REBUILD_DEBOUNCE_MS", dev_rebuild_debounce_ms_default);
    var watcher_context = DevWatcherContext{
        .root_path = root_path,
        .out_dir = out_dir,
        .watch_root_dir = watch_root_dir,
        .ignore_dir = ignore_dir,
        .watch_poll_ms = watch_poll_ms,
        .rebuild_debounce_ms = rebuild_debounce_ms,
        .state = &watch_state,
    };
    var watcher_thread = try std.Thread.spawn(.{}, devWatchLoop, .{&watcher_context});
    defer {
        watch_state.stop.store(true, .release);
        watcher_thread.join();
    }

    printDevInfo("server.starting", "starting Bun preview server", .{});

    var env_map = try parent_environ_map.clone(allocator);
    defer env_map.deinit();

    if (env_map.get("PORT")) |port| {
        printDevInfo("server.port", "port={s} source=env", .{port});
    } else {
        try env_map.put("PORT", "0");
        printDevInfo("server.port", "port=auto source=ephemeral", .{});
    }

    var child = try std.process.spawn(process_io, .{
        .argv = &.{ "bun", "--hot", "server.ts" },
        .cwd = .{ .path = out_dir },
        .environ_map = &env_map,
        .stdin = .inherit,
        .stdout = .inherit,
        .stderr = .inherit,
    });
    const term = try child.wait(process_io);
    switch (term) {
        .exited => |code| {
            if (code == 130 or code == 143) {
                printDevInfo("server.stop", "preview server stopped gracefully", .{});
                return;
            }
            if (code != 0) {
                const err_name = std.fmt.allocPrint(allocator, "ChildExitCode({d})", .{code}) catch "ChildExitCode(alloc-failed)";
                defer if (!std.mem.eql(u8, err_name, "ChildExitCode(alloc-failed)")) allocator.free(err_name);
                printCliDevMessage("dev server", root_path, .bundle, "dev.server_exit_code", err_name) catch {};
                return error.ChildProcessFailed;
            }
        },
        .signal => |sig| {
            if (sig == std.posix.SIG.INT or sig == std.posix.SIG.TERM) {
                printDevInfo("server.stop", "preview server stopped gracefully", .{});
                return;
            }
            const sig_msg = std.fmt.allocPrint(allocator, "ChildSignal({d})", .{sig}) catch "ChildSignal(alloc-failed)";
            defer if (!std.mem.eql(u8, sig_msg, "ChildSignal(alloc-failed)")) allocator.free(sig_msg);
            printCliDevMessage("dev server", root_path, .bundle, "dev.server_signal", sig_msg) catch {};
            return error.ChildProcessFailed;
        },
        .stopped => |sig| {
            if (sig == std.posix.SIG.INT or sig == std.posix.SIG.TERM) {
                printDevInfo("server.stop", "preview server stopped gracefully", .{});
                return;
            }
            const sig_msg = std.fmt.allocPrint(allocator, "ChildStoppedSignal({d})", .{sig}) catch "ChildStoppedSignal(alloc-failed)";
            defer if (!std.mem.eql(u8, sig_msg, "ChildStoppedSignal(alloc-failed)")) allocator.free(sig_msg);
            printCliDevMessage("dev server", root_path, .bundle, "dev.server_stopped_signal", sig_msg) catch {};
            return error.ChildProcessFailed;
        },
        .unknown => |status| {
            const status_msg = std.fmt.allocPrint(allocator, "ChildUnknownStatus({d})", .{status}) catch "ChildUnknownStatus(alloc-failed)";
            defer if (!std.mem.eql(u8, status_msg, "ChildUnknownStatus(alloc-failed)")) allocator.free(status_msg);
            printCliDevMessage("dev server", root_path, .bundle, "dev.server_unknown_status", status_msg) catch {};
            return error.ChildProcessFailed;
        },
    }
}

fn devWatchLoop(context: *DevWatcherContext) void {
    const allocator = std.heap.page_allocator;
    var last_handled_fingerprint = computeWatchFingerprint(context.watch_root_dir, context.ignore_dir, allocator) catch |err| {
        printCliStageError("dev watch initialize", context.root_path, .bundle, "dev.watch_init_failed", err, allocator) catch {};
        return;
    };
    var pending_fingerprint: ?u64 = null;
    var pending_since_ns: i128 = 0;
    var last_scan_error_log_ns: i128 = 0;

    while (!context.state.stop.load(.acquire)) {
        std.Io.sleep(
            std.Io.Threaded.global_single_threaded.io(),
            .fromMilliseconds(@intCast(context.watch_poll_ms)),
            .awake,
        ) catch {};
        const next_fingerprint = computeWatchFingerprint(context.watch_root_dir, context.ignore_dir, allocator) catch |err| {
            const now_ns = monotonicNowNs();
            if (last_scan_error_log_ns == 0 or now_ns - last_scan_error_log_ns >= 5 * std.time.ns_per_s) {
                printCliStageError("dev watch scan", context.root_path, .bundle, "dev.watch_scan_failed", err, allocator) catch {};
                last_scan_error_log_ns = now_ns;
            }
            continue;
        };
        last_scan_error_log_ns = 0;

        if (pending_fingerprint) |expected| {
            if (next_fingerprint == last_handled_fingerprint) {
                pending_fingerprint = null;
                continue;
            }
            if (next_fingerprint != expected) {
                pending_fingerprint = next_fingerprint;
                pending_since_ns = monotonicNowNs();
                continue;
            }
            if (monotonicNowNs() - pending_since_ns < context.rebuild_debounce_ms * std.time.ns_per_ms) {
                continue;
            }
        } else {
            if (next_fingerprint == last_handled_fingerprint) continue;
            pending_fingerprint = next_fingerprint;
            pending_since_ns = monotonicNowNs();
            printDevInfo("watch.change_detected", "waiting for files to settle", .{});
            continue;
        }

        printDevInfo("watch.rebuild", "rebuilding", .{});
        runEmitApp(context.root_path, context.out_dir, allocator) catch |err| {
            if (err == error.Reported) {
                printDevInfo("watch.rebuild_blocked", "rebuild blocked by diagnostics", .{});
            } else {
                printCliStageError("dev rebuild", context.root_path, .bundle, "dev.rebuild_failed", err, allocator) catch {};
            }
            printDevInfo("watch.resume", "watching for the next change", .{});
            last_handled_fingerprint = next_fingerprint;
            pending_fingerprint = null;
            continue;
        };
        printDevInfo("watch.rebuild_complete", "rebuild complete", .{});
        printDevInfo("watch.resume", "watching for the next change", .{});
        last_handled_fingerprint = next_fingerprint;
        pending_fingerprint = null;
    }
}

fn monotonicNowNs() i128 {
    return @intCast(std.Io.Clock.awake.now(std.Io.Threaded.global_single_threaded.io()).toNanoseconds());
}

fn printDevInfo(comptime event: []const u8, comptime fmt: []const u8, args: anytype) void {
    std.debug.print("weiv dev info {s}: " ++ fmt ++ "\n", .{event} ++ args);
}

fn printCliDevMessage(
    action: []const u8,
    source_path: []const u8,
    stage: compiler_diagnostics.Stage,
    code: []const u8,
    detail: []const u8,
) !void {
    var bag = compiler_diagnostics.DiagnosticBag.init();
    defer bag.deinit(std.heap.page_allocator);
    try bag.appendOwned(
        std.heap.page_allocator,
        code,
        .@"error",
        detail,
        stage,
        source_path,
        null,
        null,
        true,
    );
    const diagnostics = try bag.toOwnedSlice(std.heap.page_allocator);
    defer {
        for (diagnostics) |*diagnostic| diagnostic.deinit(std.heap.page_allocator);
        std.heap.page_allocator.free(diagnostics);
    }
    try printComponentDiagnosticsFailure(action, source_path, diagnostics);
}

fn computeWatchFingerprint(
    root_dir_path: []const u8,
    ignore_dir: ?[]const u8,
    allocator: std.mem.Allocator,
) !u64 {
    var dir = try std.Io.Dir.openDirAbsolute(std.Io.Threaded.global_single_threaded.io(), root_dir_path, .{ .iterate = true });
    defer dir.close(std.Io.Threaded.global_single_threaded.io());

    var walker = try dir.walk(allocator);
    defer walker.deinit();

    var hasher = std.hash.Wyhash.init(0);
    while (try walker.next(std.Io.Threaded.global_single_threaded.io())) |entry| {
        if (entry.kind != .file) continue;
        if (shouldIgnoreWatchedPath(root_dir_path, entry.path, ignore_dir, allocator)) continue;
        if (!isWatchRelevantFile(entry.path)) continue;

        const stat = try dir.statFile(std.Io.Threaded.global_single_threaded.io(), entry.path, .{});
        hasher.update(entry.path);
        hasher.update(std.mem.asBytes(&stat.size));
        hasher.update(std.mem.asBytes(&stat.mtime));
    }
    return hasher.final();
}

fn shouldIgnoreWatchedPath(
    root_dir_path: []const u8,
    relative_path: []const u8,
    ignore_dir: ?[]const u8,
    allocator: std.mem.Allocator,
) bool {
    if (std.mem.indexOf(u8, relative_path, "node_modules") != null) return true;
    if (std.mem.indexOf(u8, relative_path, ".git") != null) return true;

    const ignored = ignore_dir orelse return false;
    const abs_path = std.fs.path.join(allocator, &.{ root_dir_path, relative_path }) catch return false;
    defer allocator.free(abs_path);
    return std.mem.startsWith(u8, abs_path, ignored) and
        (abs_path.len == ignored.len or abs_path[ignored.len] == std.fs.path.sep);
}

fn isWatchRelevantFile(path: []const u8) bool {
    return std.mem.endsWith(u8, path, ".weiv") or
        std.mem.endsWith(u8, path, ".ts") or
        std.mem.endsWith(u8, path, ".mts") or
        std.mem.endsWith(u8, path, ".js") or
        std.mem.endsWith(u8, path, ".mjs") or
        std.mem.endsWith(u8, path, ".css") or
        std.mem.endsWith(u8, path, ".json") or
        std.mem.endsWith(u8, path, ".html");
}

fn readDevTimingEnvU64(name: []const u8, default_value: u64) u64 {
    const name_z = std.heap.page_allocator.dupeZ(u8, name) catch return default_value;
    defer std.heap.page_allocator.free(name_z);
    const raw_value = std.c.getenv(name_z.ptr) orelse return default_value;
    const value = std.mem.span(raw_value);
    return std.fmt.parseUnsigned(u64, value, 10) catch default_value;
}

pub fn formatComponentAnalysisReport(model: component.ComponentUnit, allocator: std.mem.Allocator) ![]u8 {
    var out = std.Io.Writer.Allocating.init(allocator);
    defer out.deinit();
    const writer = &out.writer;

    try writer.print("SFC sections\n", .{});
    try writer.print("  template: {d}..{d}\n", .{ model.sfc_document.template.content_span.start, model.sfc_document.template.content_span.end });
    try writer.print("  script:   {d}..{d}\n", .{ model.sfc_document.script.content_span.start, model.sfc_document.script.content_span.end });
    if (model.sfc_document.style) |style_section| {
        try writer.print("  style:    {d}..{d}\n", .{ style_section.content_span.start, style_section.content_span.end });
    } else {
        try writer.writeAll("  style:    <none>\n");
    }

    try writer.print("Template AST\n  root nodes: {d}\n", .{model.template_document.nodes.len});
    try writer.print("Normalized template\n", .{});
    try printNormalizedNodes(model.normalized_template.nodes, 1, writer);
    try writer.print("Script analysis\n  ok: {any}\n", .{model.script.ok});
    if (model.script.props) |props| {
        try writer.print("  props export: {any}\n", .{props.has_props_export});
        if (props.props_type_name) |type_name| {
            try writer.print("  props type: {s}\n", .{type_name});
        }
    }
    try writer.print("  imports: {d}\n", .{model.script.imports.len});
    try writer.print("  bindings: {d}\n", .{model.script.bindings.len});
    for (model.script.bindings) |binding| {
        try writer.print("    - {s} [{s}]\n", .{ binding.name, binding.kind });
    }
    try writer.print("  diagnostics: {d}\n", .{model.script.diagnostics.len});
    for (model.script.diagnostics) |diagnostic| {
        if (diagnostic.code) |code| {
            try writer.print("    - {s} {s}: {s} [{d}:{d}] [{d}..{d}]\n", .{
                diagnostic.severity,
                code,
                diagnostic.message,
                diagnostic.line,
                diagnostic.column,
                diagnostic.span_start,
                diagnostic.span_end,
            });
        } else {
            try writer.print("    - {s}: {s} [{d}:{d}] [{d}..{d}]\n", .{
                diagnostic.severity,
                diagnostic.message,
                diagnostic.line,
                diagnostic.column,
                diagnostic.span_start,
                diagnostic.span_end,
            });
        }
    }
    try writer.print("Binding phase\n  component refs: {d}\n", .{model.template_bindings.component_refs.len});
    for (model.template_bindings.component_refs) |component_ref| {
        try writer.print("    - {s} resolved={any}\n", .{ component_ref.tag_name, component_ref.resolved });
    }
    try writer.print("  binding diagnostics: {d}\n", .{model.template_bindings.diagnostics.len});
    for (model.template_bindings.diagnostics) |diagnostic| {
        try writer.print("    - {s} {s}: {s} — {s} [{d}..{d}]\n", .{
            diagnostic.severity,
            diagnostic.kind,
            diagnostic.name,
            diagnostic.message,
            diagnostic.span.start,
            diagnostic.span.end,
        });
    }
    try appendProxyStateSummary(&model, writer, allocator);

    return out.toOwnedSlice();
}

pub fn formatComponentCompileReport(report: component.ComponentCompileReport, allocator: std.mem.Allocator) ![]u8 {
    var out = std.Io.Writer.Allocating.init(allocator);
    defer out.deinit();
    const writer = &out.writer;

    if (report.sfc_document) |sfc_document| {
        try writer.print("SFC sections\n", .{});
        try writer.print("  template: {d}..{d}\n", .{ sfc_document.template.content_span.start, sfc_document.template.content_span.end });
        try writer.print("  script:   {d}..{d}\n", .{ sfc_document.script.content_span.start, sfc_document.script.content_span.end });
        if (sfc_document.style) |style_section| {
            try writer.print("  style:    {d}..{d}\n", .{ style_section.content_span.start, style_section.content_span.end });
        } else {
            try writer.writeAll("  style:    <none>\n");
        }
    }

    if (report.template_document) |template_document| {
        try writer.print("Template AST\n  root nodes: {d}\n", .{template_document.nodes.len});
    }

    if (report.normalized_template) |normalized_template| {
        try writer.print("Normalized template\n", .{});
        try printNormalizedNodes(normalized_template.nodes, 1, writer);
    }

    if (report.script) |script| {
        try writer.print("Script analysis\n  ok: {any}\n", .{script.ok});
        if (script.props) |props| {
            try writer.print("  props export: {any}\n", .{props.has_props_export});
            if (props.props_type_name) |type_name| {
                try writer.print("  props type: {s}\n", .{type_name});
            }
        }
        try writer.print("  imports: {d}\n", .{script.imports.len});
        try writer.print("  bindings: {d}\n", .{script.bindings.len});
        for (script.bindings) |binding_record| {
            try writer.print("    - {s} [{s}]\n", .{ binding_record.name, binding_record.kind });
        }
        try writer.print("  diagnostics: {d}\n", .{script.diagnostics.len});
        for (script.diagnostics) |diagnostic| {
            if (diagnostic.code) |code| {
                try writer.print("    - {s} {s}: {s} [{d}:{d}] [{d}..{d}]\n", .{
                    diagnostic.severity,
                    code,
                    diagnostic.message,
                    diagnostic.line,
                    diagnostic.column,
                    diagnostic.span_start,
                    diagnostic.span_end,
                });
            } else {
                try writer.print("    - {s}: {s} [{d}:{d}] [{d}..{d}]\n", .{
                    diagnostic.severity,
                    diagnostic.message,
                    diagnostic.line,
                    diagnostic.column,
                    diagnostic.span_start,
                    diagnostic.span_end,
                });
            }
        }
    }

    if (report.template_bindings) |template_bindings| {
        try writer.print("Binding phase\n  component refs: {d}\n", .{template_bindings.component_refs.len});
        for (template_bindings.component_refs) |component_ref| {
            try writer.print("    - {s} resolved={any}\n", .{ component_ref.tag_name, component_ref.resolved });
        }
        try writer.print("  binding diagnostics: {d}\n", .{template_bindings.diagnostics.len});
        for (template_bindings.diagnostics) |diagnostic| {
            try writer.print("    - {s} {s}: {s} — {s} [{d}..{d}]\n", .{
                diagnostic.severity,
                diagnostic.kind,
                diagnostic.name,
                diagnostic.message,
                diagnostic.span.start,
                diagnostic.span.end,
            });
        }
    }

    try writer.print("Compiler diagnostics\n  total: {d}\n", .{report.diagnostics.len});
    try compiler_diagnostics.writeTextDiagnostics(writer, report.diagnostics, "    - ");

    if (report.lir_document != null and report.template_bindings != null) {
        const success_model = component.ComponentUnit{
            .source_path = report.source_path,
            .source = report.source.?,
            .sfc_document = report.sfc_document.?,
            .template_document = report.template_document.?,
            .normalized_template = report.normalized_template.?,
            .script = report.script.?,
            .script_js = report.script_js.?,
            .template_bindings = report.template_bindings.?,
            .lir_document = report.lir_document.?,
        };
        try appendProxyStateSummary(&success_model, writer, allocator);
    } else if (report.halted_after) |halted_after| {
        try writer.print("Pipeline halt\n  halted after: {s}\n", .{compiler_diagnostics.stageLabel(halted_after)});
    }

    return out.toOwnedSlice();
}

fn appendProxyStateSummary(
    model: *const component.ComponentUnit,
    writer: anytype,
    allocator: std.mem.Allocator,
) !void {
    var render_tree = try browser_render_tree.lower(&model.lir_document, allocator);
    defer render_tree.deinit(allocator);

    const formatted = try invalidation_graph.formatDocument(model, &render_tree, allocator);
    defer allocator.free(formatted);

    var tracked_root_lines = std.ArrayList([]const u8).empty;
    defer tracked_root_lines.deinit(allocator);
    var imported_root_count: usize = 0;
    var prop_root_count: usize = 0;
    var local_root_count: usize = 0;

    const Section = enum {
        none,
        tracked_roots,
        diagnostics,
    };

    var section: Section = .none;
    var lines = std.mem.tokenizeScalar(u8, formatted, '\n');
    while (lines.next()) |line| {
        if (std.mem.eql(u8, line, "tracked-roots")) {
            section = .tracked_roots;
            continue;
        }
        if (std.mem.eql(u8, line, "diagnostics")) {
            section = .diagnostics;
            continue;
        }
        if (isInvalidationGraphTopLevelSection(line)) {
            section = .none;
            continue;
        }

        switch (section) {
            .tracked_roots => {
                if (std.mem.startsWith(u8, line, "  root ")) {
                    try tracked_root_lines.append(allocator, line["  ".len..]);
                    if (std.mem.indexOf(u8, line, "kind=imported-tracked") != null) imported_root_count += 1;
                    if (std.mem.indexOf(u8, line, "kind=prop-tracked") != null) prop_root_count += 1;
                    if (std.mem.indexOf(u8, line, "kind=local-tracked") != null) local_root_count += 1;
                }
            },
            .diagnostics => {},
            .none => {},
        }
    }

    try writer.print("Proxy state graph\n", .{});
    try writer.print("  tracked roots: {d}\n", .{tracked_root_lines.items.len});
    try writer.print("  root kinds: imported={d} props={d} local={d}\n", .{
        imported_root_count,
        prop_root_count,
        local_root_count,
    });
    for (tracked_root_lines.items) |line| {
        try writer.print("    - {s}\n", .{line});
    }
}

fn isInvalidationGraphTopLevelSection(line: []const u8) bool {
    if (line.len == 0) return false;
    return line[0] != ' ' and
        !std.mem.startsWith(u8, line, "invalidation-graph source=");
}

fn printComponentAnalysis(model: component.ComponentUnit) !void {
    var stdout = std.Io.File.stdout();
    const formatted = try formatComponentAnalysisReport(model, std.heap.page_allocator);
    defer std.heap.page_allocator.free(formatted);
    try stdout.writeStreamingAll(std.Io.Threaded.global_single_threaded.io(), formatted);
}

fn printComponentAnalysisReport(report: component.ComponentCompileReport) !void {
    var stdout = std.Io.File.stdout();
    const formatted = try formatComponentCompileReport(report, std.heap.page_allocator);
    defer std.heap.page_allocator.free(formatted);
    try stdout.writeStreamingAll(std.Io.Threaded.global_single_threaded.io(), formatted);
}

pub fn formatComponentCompileReportJson(report: component.ComponentCompileReport, allocator: std.mem.Allocator) ![]u8 {
    var out = std.Io.Writer.Allocating.init(allocator);
    defer out.deinit();
    const writer = &out.writer;

    try writer.writeAll("{\n");
    try writer.print("  \"sourcePath\": {f},\n", .{std.json.fmt(report.source_path, .{})});
    if (report.halted_after) |stage| {
        try writer.print("  \"haltedAfter\": {f},\n", .{std.json.fmt(compiler_diagnostics.stageLabel(stage), .{})});
    } else {
        try writer.writeAll("  \"haltedAfter\": null,\n");
    }
    try writer.writeAll("  \"stages\": {\n");
    try writer.print("    \"sfc\": {any},\n", .{report.sfc_document != null});
    try writer.print("    \"template\": {any},\n", .{report.template_document != null});
    try writer.print("    \"normalizedTemplate\": {any},\n", .{report.normalized_template != null});
    try writer.print("    \"script\": {any},\n", .{report.script != null});
    try writer.print("    \"binding\": {any},\n", .{report.template_bindings != null});
    try writer.print("    \"lir\": {any}\n", .{report.lir_document != null});
    try writer.writeAll("  },\n");
    try writer.writeAll("  \"diagnostics\": [\n");
    try compiler_diagnostics.writeJsonDiagnostics(writer, report.diagnostics, "    ");
    try writer.writeAll("  ]\n");
    try writer.writeAll("}\n");
    return out.toOwnedSlice();
}

fn printComponentAnalysisJson(report: component.ComponentCompileReport) !void {
    var stdout = std.Io.File.stdout();
    const formatted = try formatComponentCompileReportJson(report, std.heap.page_allocator);
    defer std.heap.page_allocator.free(formatted);
    try stdout.writeStreamingAll(std.Io.Threaded.global_single_threaded.io(), formatted);
}

fn printNormalizedNodes(nodes: []const parser.template.NormalizedNode, indent: usize, writer: anytype) !void {
    for (nodes) |node| {
        try printIndent(indent, writer);
        switch (node) {
            .text => |text| try writer.print("text [{d}..{d}]\n", .{ text.span.start, text.span.end }),
            .interpolation => |interp| try writer.print("interpolation `{s}` [{d}..{d}]\n", .{ interp.expression, interp.span.start, interp.span.end }),
            .slot_outlet => |slot_outlet| {
                if (slot_outlet.name) |name| {
                    try writer.print("slot name=\"{s}\"\n", .{name});
                } else {
                    try writer.print("slot <default>\n", .{});
                }
                try printNormalizedNodes(slot_outlet.fallback_children, indent + 1, writer);
            },
            .element => |element| {
                try writer.print("element <{s}> children={d}\n", .{ element.tag_name, element.children.len });
                for (element.directives) |directive| {
                    try printIndent(indent + 1, writer);
                    switch (directive) {
                        .bind => |bind_dir| try writer.print("directive bind:{s}=\"{s}\"\n", .{ bind_dir.target_name, bind_dir.expression }),
                        .event => |event_dir| try writer.print("directive on:{s}=\"{s}\"\n", .{ event_dir.event_name, event_dir.expression }),
                        .slot_assign => |slot_assign| try writer.print("directive slot:{s}\n", .{slot_assign.slot_name}),
                        .if_expr, .else_branch, .for_expr => unreachable,
                    }
                }
                try printNormalizedNodes(element.children, indent + 1, writer);
            },
            .conditional => |conditional| {
                try writer.print("conditional if=\"{s}\"\n", .{conditional.condition});
                try printIndent(indent + 1, writer);
                try writer.print("consequent\n", .{});
                try printNormalizedNodes(conditional.consequent, indent + 2, writer);
                if (conditional.alternate.len > 0) {
                    try printIndent(indent + 1, writer);
                    try writer.print("alternate\n", .{});
                    try printNormalizedNodes(conditional.alternate, indent + 2, writer);
                }
            },
            .for_loop => |for_loop| {
                try writer.print("for {s} in {s}\n", .{ for_loop.item_name, for_loop.iterable_expr });
                try printNormalizedNodes(for_loop.body, indent + 1, writer);
            },
        }
    }
}

fn printIndent(indent: usize, writer: anytype) !void {
    var i: usize = 0;
    while (i < indent) : (i += 1) {
        try writer.writeAll("  ");
    }
}

fn rejectRetiredReactivityCommand(name: []const u8) !void {
    if (std.mem.endsWith(u8, name, "-legacy") or std.mem.eql(u8, name, "js-cells") or std.mem.eql(u8, name, "app-cells")) {
        try printComponentDiagnosticsFailure("emit", name, &.{.{
            .code = "cli.reactivity_mode_removed",
            .severity = .@"error",
            .message = "This reactivity mode has been removed. Use emit js or emit app, remove weivUpdate wrappers, and wait for the queued DOM batch before reading updated DOM.",
            .stage = .emit,
            .source_path = name,
            .span = null,
            .location = null,
            .fatal = true,
        }});
        return error.Reported;
    }
}
