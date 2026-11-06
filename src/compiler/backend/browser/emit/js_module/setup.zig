const std = @import("std");
const component = @import("../../../../component_unit.zig");
const tracked_roots = @import("../../tracked_roots.zig");
const common = @import("common.zig");

pub fn buildTemplateBindingsJson(unit: *const component.ComponentUnit, allocator: std.mem.Allocator) ![]u8 {
    var json = std.ArrayList(u8).empty;
    defer json.deinit(allocator);
    try json.append(allocator, '[');
    var first = true;
    for (unit.script.bindings) |binding| {
        if (!binding.template_visible) continue;
        if (!first) try json.append(allocator, ',');
        try json.append(allocator, '"');
        try json.appendSlice(allocator, binding.name);
        try json.append(allocator, '"');
        first = false;
    }
    try json.append(allocator, ']');
    return try json.toOwnedSlice(allocator);
}

pub fn isCellBinding(model: *const component.ComponentUnit, binding: @import("../../../../sema/sir.zig").ScriptBinding) bool {
    if (!binding.template_visible) return false;
    if (!std.mem.eql(u8, binding.kind, "mutable") and !std.mem.eql(u8, binding.kind, "immutable")) return false;
    if (tracked_roots.isPropsBinding(model, binding.name)) return false;
    return true;
}

fn selectedCellBinding(model: *const component.ComponentUnit, binding: @import("../../../../sema/sir.zig").ScriptBinding, names: ?[]const []const u8) bool {
    if (!isCellBinding(model, binding)) return false;
    if (names) |selected| {
        for (selected) |name| if (std.mem.eql(u8, name, binding.name)) return true;
        return false;
    }
    return true;
}

pub fn buildCellNames(model: *const component.ComponentUnit, local_names: ?[]const []const u8, allocator: std.mem.Allocator) ![]u8 {
    var names = std.ArrayList(u8).empty;
    defer names.deinit(allocator);
    try names.append(allocator, '[');
    var first = true;
    for (model.script.bindings) |binding| {
        if (!selectedCellBinding(model, binding, local_names)) continue;
        if (!first) try names.append(allocator, ',');
        first = false;
        try common.emitString(binding.name, &names, allocator);
    }
    try names.append(allocator, ']');
    return names.toOwnedSlice(allocator);
}

pub fn buildSetupCode(model: *const component.ComponentUnit, allocator: std.mem.Allocator) ![]u8 {
    return buildSetupCodeWithCells(model, false, allocator);
}

pub fn buildSetupCodeWithCells(model: *const component.ComponentUnit, cells: bool, allocator: std.mem.Allocator) ![]u8 {
    return buildSetupCodeWithSubscriptions(model, cells, &.{}, allocator);
}

pub fn buildSetupCodeWithSubscriptions(model: *const component.ComponentUnit, cells: bool, subscriptions: []const @import("../js_module.zig").ManagedSubscription, allocator: std.mem.Allocator) ![]u8 {
    return buildSetupCodeWithSelection(model, cells, subscriptions, null, &.{}, allocator);
}

pub fn buildSetupCodeWithSelection(model: *const component.ComponentUnit, cells: bool, subscriptions: []const @import("../js_module.zig").ManagedSubscription, local_names: ?[]const []const u8, local_subscriptions: []const @import("../js_module.zig").LocalSubscription, allocator: std.mem.Allocator) ![]u8 {
    return buildSetupCodeWithExpressions(model, cells, subscriptions, local_names, local_subscriptions, "", allocator);
}

pub fn buildSetupCodeWithExpressions(model: *const component.ComponentUnit, cells: bool, subscriptions: []const @import("../js_module.zig").ManagedSubscription, local_names: ?[]const []const u8, local_subscriptions: []const @import("../js_module.zig").LocalSubscription, expressions: []const u8, allocator: std.mem.Allocator) ![]u8 {
    var out = std.ArrayList(u8).empty;
    defer out.deinit(allocator);

    try out.appendSlice(allocator,
        \\function setup(__weiv_props, __weiv_event_handlers = {}) {
        \\  let props = __weiv_props;
        \\  let __weiv_handlers = __weiv_event_handlers;
        \\  let __weiv_runBoundary = (callback) => callback();
        \\  const weivUpdate = (callback) => __weiv_runBoundary(callback);
    );
    if (!cells) try out.appendSlice(allocator,
        \\  const __weiv_wrapCallback = (callback) => {
        \\    if (typeof callback !== "function") {
        \\      return callback;
        \\    }
        \\    return (...args) => __weiv_runBoundary(() => callback(...args));
        \\  };
        \\  const setTimeout = (callback, ...args) => globalThis.setTimeout(__weiv_wrapCallback(callback), ...args);
        \\  const setInterval = (callback, ...args) => globalThis.setInterval(__weiv_wrapCallback(callback), ...args);
        \\  const queueMicrotask = (callback) => globalThis.queueMicrotask(__weiv_wrapCallback(callback));
        \\  const requestAnimationFrame = (callback) => globalThis.requestAnimationFrame(__weiv_wrapCallback(callback));
    );
    try out.appendSlice(allocator,
        \\  const emit = (name, payload) => {
        \\    if (typeof __weiv_handlers[name] === "function") {
        \\      return __weiv_handlers[name](payload);
        \\    }
        \\    return undefined;
        \\  };
        \\
    );

    for (model.script.imports) |import_record| {
        if (import_record.local_name.len == 0) continue;
        if (std.mem.endsWith(u8, import_record.source, ".weiv")) continue;
        if (!common.shouldPreserveImport(import_record, &model.script)) continue;
        if (!cells) {
            try out.print(allocator, "  const {s} = __weiv_getTrackedRoot(\"{s}\", __weiv_import_{s});\n", .{
                import_record.local_name,
                import_record.local_name,
                import_record.local_name,
            });
        }
    }

    const cell_names = try buildCellNames(model, if (cells) local_names else &.{}, allocator);
    defer allocator.free(cell_names);
    const lowered_script = if (cells) try @import("../../../../../ffi/script_backend.zig").lowerCellsWithExpressions(model.sfc_document.script.content, model.source_path, cell_names, expressions, allocator) else null;
    defer if (lowered_script) |script| allocator.free(script);
    if (lowered_script) |script| {
        // The backend removes module declarations as syntax. Preserve literal
        // newlines and indentation instead of classifying lines of source text.
        try out.appendSlice(allocator, script);
        try out.appendSlice(allocator, "\n");
    }
    var lines = std.mem.tokenizeScalar(u8, if (cells) "" else model.script_js, '\n');
    while (lines.next()) |line_raw| {
        const line = std.mem.trim(u8, line_raw, &std.ascii.whitespace);
        if (line.len == 0) continue;
        if (std.mem.startsWith(u8, line, "import ")) continue;
        if (std.mem.startsWith(u8, line, "export let props")) continue;
        if (std.mem.startsWith(u8, line, "export ")) {
            try out.appendSlice(allocator, "  ");
            try out.appendSlice(allocator, line["export ".len..]);
            try out.appendSlice(allocator, "\n");
            continue;
        }
        try out.appendSlice(allocator, "  ");
        var emitted_line = line;
        if (!cells and std.mem.startsWith(u8, line, "const ")) {
            for (model.script.bindings) |binding| {
                if (!std.mem.eql(u8, binding.kind, "immutable")) continue;
                if (!tracked_roots.isLocalTrackedBinding(model, binding.name)) continue;
                if (!std.mem.startsWith(u8, line["const ".len..], binding.name)) continue;
                const suffix = line["const ".len + binding.name.len ..];
                if (suffix.len == 0 or (suffix[0] != ' ' and suffix[0] != '=' and suffix[0] != ':')) continue;
                try out.appendSlice(allocator, "let ");
                emitted_line = line["const ".len..];
                break;
            }
        }
        try out.appendSlice(allocator, emitted_line);
        try out.appendSlice(allocator, "\n");
    }

    if (!cells) for (model.script.bindings) |binding| {
        if (!binding.callable or !std.mem.eql(u8, binding.kind, "function")) continue;
        if (!isAsyncHelper(model, binding.name)) continue;
        try out.print(
            allocator,
            "  {s} = __weiv_wrapCallback({s});\n",
            .{ binding.name, binding.name },
        );
    };

    if (model.script.props) |props_record| {
        if (props_record.props_binding_name) |binding_name| {
            try out.print(allocator, "  props = __weiv_getTrackedRoot(\"{s}\", props);\n", .{binding_name});
        }
    }
    for (model.script.bindings) |binding| {
        if (!tracked_roots.isLocalTrackedBinding(model, binding.name)) continue;
        if (cells) continue;
        try out.print(allocator, "  {s} = __weiv_getTrackedRoot(\"{s}\", {s});\n", .{
            binding.name,
            binding.name,
            binding.name,
        });
    }

    try out.appendSlice(allocator, "  const __weiv_scope = {__proto__: null};\n");
    if (cells and expressions.len > 0) try out.appendSlice(allocator, "  __weiv_scope.__weiv_eval = __weiv_templateExpressions;\n");
    try out.appendSlice(allocator, "  function __weiv_refresh() {\n");
    try out.appendSlice(allocator, "    __weiv_scope.props = props;\n");
    try out.appendSlice(allocator, "    __weiv_scope.emit = emit;\n");
    for (model.script.imports) |import_record| {
        if (import_record.local_name.len == 0) continue;
        if (std.mem.endsWith(u8, import_record.source, ".weiv")) continue;
        if (!common.shouldPreserveImport(import_record, &model.script)) continue;
        try out.print(allocator, "    __weiv_scope.{s} = {s}{s};\n", .{ import_record.local_name, if (cells) "__weiv_import_" else "", import_record.local_name });
    }
    for (model.script.bindings) |binding| {
        if (binding.template_visible and !std.mem.eql(u8, binding.kind, "import")) {
            try out.print(allocator, "    __weiv_scope.{s} = {s}{s};\n", .{ binding.name, binding.name, if (cells and selectedCellBinding(model, binding, local_names)) ".value" else "" });
        }
    }
    try out.appendSlice(allocator, "    return __weiv_scope;\n");
    try out.appendSlice(allocator, "  }\n");
    try out.appendSlice(allocator, "  function __weiv_setProps(nextProps) {\n");
    if (model.script.props) |props_record| {
        if (props_record.props_binding_name) |binding_name| {
            try out.print(allocator, "    props = __weiv_getTrackedRoot(\"{s}\", nextProps);\n", .{binding_name});
        } else {
            try out.appendSlice(allocator, "    props = nextProps;\n");
        }
    } else {
        try out.appendSlice(allocator, "    props = nextProps;\n");
    }
    try out.appendSlice(allocator, "  }\n");
    try out.appendSlice(allocator, "  function __weiv_setEventHandlers(nextHandlers) {\n    __weiv_handlers = nextHandlers;\n  }\n");
    try out.appendSlice(allocator, "  function __weiv_setBoundaryRunner(nextRunner) {\n    __weiv_runBoundary = nextRunner;\n  }\n");
    try out.appendSlice(allocator, if (cells) "  function __weiv_subscribeImportedObservables(__weiv_instance) {\n" else "  function __weiv_subscribeImportedObservables(instance) {\n");
    if (cells) {
        try out.appendSlice(allocator, "    const __weiv_cellScope = __weiv_createCellScope((dirty) => { if (!__weiv_instance.destroyed) __weiv_instance.updateDirty({ bindings: [...dirty], paths: [] }, __weiv_instance.refresh()); });\n");
        for (model.script.bindings) |binding| {
            if (local_names == null and selectedCellBinding(model, binding, local_names)) try out.print(allocator, "    __weiv_cellScope.watch({s}, \"{s}\");\n", .{ binding.name, binding.name });
        }
        for (local_subscriptions) |subscription| {
            for (model.script.bindings) |binding| {
                if (!std.mem.eql(u8, binding.name, subscription.name) or !selectedCellBinding(model, binding, local_names)) continue;
                try out.print(allocator, "    __weiv_cellScope.watch({s}, ", .{subscription.name});
                try common.emitString(subscription.binding, &out, allocator);
                try out.appendSlice(allocator, ");\n");
            }
        }
        for (subscriptions, 0..) |subscription, index| {
            try out.print(allocator, "    __weiv_cellScope.watch(__weiv_publisher_{d}.getCell(", .{index});
            try common.emitString(subscription.name, &out, allocator);
            try out.appendSlice(allocator, "), ");
            try common.emitString(subscription.binding, &out, allocator);
            try out.appendSlice(allocator, ");\n");
        }
        imports: for (model.script.imports) |record| {
            if (record.local_name.len == 0 or !common.shouldPreserveImport(record, &model.script)) continue;
            if (std.mem.endsWith(u8, record.source, ".weiv")) continue;
            var watched = local_names == null;
            for (local_subscriptions) |subscription| {
                if (subscription.publisher_backed and std.mem.eql(u8, subscription.name, record.local_name)) continue :imports;
                if (std.mem.eql(u8, subscription.name, record.local_name)) watched = true;
            }
            if (!watched) continue;
            try out.print(allocator, "    if (__weiv_isObservable(__weiv_import_{s})) {{ const __weiv_importedCell = __weiv_createCell(__weiv_import_{s});\n", .{ record.local_name, record.local_name });
            if (local_names == null) {
                try out.appendSlice(allocator, "      __weiv_cellScope.watch(__weiv_importedCell, ");
                try common.emitString(record.local_name, &out, allocator);
                try out.appendSlice(allocator, ");\n");
            }
            for (local_subscriptions) |subscription| {
                if (!std.mem.eql(u8, subscription.name, record.local_name)) continue;
                try out.appendSlice(allocator, "      __weiv_cellScope.watch(__weiv_importedCell, ");
                try common.emitString(subscription.binding, &out, allocator);
                try out.appendSlice(allocator, ");\n");
            }
            try out.appendSlice(allocator, "    }\n");
        }
        try out.appendSlice(allocator, "    return () => __weiv_cellScope.dispose();\n");
    }
    if (!cells) {
        try out.appendSlice(allocator, "    const __weiv_unsubscribes = [];\n");
        try out.appendSlice(allocator, "    const __weiv_seen = new Map();\n");
        try out.appendSlice(allocator, "    const __weiv_register = (bindingName, value) => {\n");
        try out.appendSlice(allocator, "      const __weiv_node = __weiv_getObservableNode(value);\n");
        try out.appendSlice(allocator, "      if (!__weiv_node || !__weiv_node.listeners || typeof __weiv_node.listeners.add !== \"function\") {\n");
        try out.appendSlice(allocator, "        return;\n");
        try out.appendSlice(allocator, "      }\n");
        try out.appendSlice(allocator, "      const __weiv_existingNames = __weiv_seen.get(__weiv_node);\n");
        try out.appendSlice(allocator, "      if (__weiv_existingNames) { __weiv_existingNames.add(bindingName); return; }\n");
        try out.appendSlice(allocator, "      const __weiv_bindingNames = new Set([bindingName]);\n");
        try out.appendSlice(allocator, "      __weiv_seen.set(__weiv_node, __weiv_bindingNames);\n");
        try out.appendSlice(allocator, "      const __weiv_listener = (changedPaths) => {\n");
        try out.appendSlice(allocator, "        if (instance.destroyed) {\n");
        try out.appendSlice(allocator, "          return;\n");
        try out.appendSlice(allocator, "        }\n");
        try out.appendSlice(allocator, "        if (typeof instance.updateDirty === \"function\") {\n");
        try out.appendSlice(allocator, "          const __weiv_preciseNames = changedPaths instanceof Set ? Array.from(__weiv_bindingNames) : [];\n");
        try out.appendSlice(allocator, "          const __weiv_dirtyPaths = new Set();\n");
        try out.appendSlice(allocator, "          if (__weiv_preciseNames.length > 0 && trackedStateGraph && Array.isArray(trackedStateGraph.paths)) {\n");
        try out.appendSlice(allocator, "            for (const __weiv_name of __weiv_preciseNames) {\n");
        try out.appendSlice(allocator, "              for (const __weiv_changedPath of changedPaths) {\n");
        try out.appendSlice(allocator, "                const __weiv_fullPath = `${__weiv_name}.${__weiv_changedPath}`;\n");
        try out.appendSlice(allocator, "                for (const __weiv_record of trackedStateGraph.paths) {\n");
        try out.appendSlice(allocator, "                  if (__weiv_record.path === __weiv_fullPath || __weiv_record.path.startsWith(`${__weiv_fullPath}.`) || __weiv_fullPath.startsWith(`${__weiv_record.path}.`)) __weiv_dirtyPaths.add(__weiv_record.pathId);\n");
        try out.appendSlice(allocator, "                }\n");
        try out.appendSlice(allocator, "              }\n");
        try out.appendSlice(allocator, "            }\n");
        try out.appendSlice(allocator, "          }\n");
        try out.appendSlice(allocator, "          instance.updateDirty({ bindings: Array.from(__weiv_bindingNames), paths: Array.from(__weiv_dirtyPaths), preciseBindings: __weiv_preciseNames }, instance.refresh());\n");
        try out.appendSlice(allocator, "        } else if (typeof instance.update === \"function\") {\n");
        try out.appendSlice(allocator, "          instance.update();\n");
        try out.appendSlice(allocator, "        }\n");
        try out.appendSlice(allocator, "      };\n");
        try out.appendSlice(allocator, "      __weiv_node.listeners.add(__weiv_listener);\n");
        try out.appendSlice(allocator, "      __weiv_unsubscribes.push(() => __weiv_node.listeners.delete(__weiv_listener));\n");
        try out.appendSlice(allocator, "    };\n");
        for (model.script.imports) |import_record| {
            if (import_record.local_name.len == 0) continue;
            if (std.mem.endsWith(u8, import_record.source, ".weiv")) continue;
            if (!common.shouldPreserveImport(import_record, &model.script)) continue;
            try out.print(allocator, "    __weiv_register(\"{s}\", {s});\n", .{ import_record.local_name, import_record.local_name });
        }
        try out.appendSlice(allocator, "    return () => {\n");
        try out.appendSlice(allocator, "      for (const __weiv_unsubscribe of __weiv_unsubscribes) {\n");
        try out.appendSlice(allocator, "        __weiv_unsubscribe();\n");
        try out.appendSlice(allocator, "      }\n");
        try out.appendSlice(allocator, "    };\n");
    }
    try out.appendSlice(allocator, "  }\n");
    try out.appendSlice(allocator, "  return { scope: __weiv_scope, refresh: __weiv_refresh, setProps: __weiv_setProps, setEventHandlers: __weiv_setEventHandlers, setBoundaryRunner: __weiv_setBoundaryRunner, subscribeImportedObservables: __weiv_subscribeImportedObservables };\n}\n");

    return try out.toOwnedSlice(allocator);
}

fn isAsyncHelper(model: *const component.ComponentUnit, name: []const u8) bool {
    for (model.script.state_facts.helpers) |helper| {
        if (std.mem.eql(u8, helper.name, name)) return helper.async_flag;
    }
    return false;
}

pub fn buildPreservedImports(model: *const component.ComponentUnit, allocator: std.mem.Allocator) ![]u8 {
    return buildPreservedImportsWithOverrides(model, &.{}, allocator);
}

pub fn buildPreservedImportsWithOverrides(model: *const component.ComponentUnit, overrides: []const @import("../js_module.zig").ImportOverride, allocator: std.mem.Allocator) ![]u8 {
    var out = std.ArrayList(u8).empty;
    defer out.deinit(allocator);

    for (model.script.imports) |record| {
        if (!common.shouldPreserveImport(record, &model.script)) continue;
        var target: ?[]const u8 = null;
        for (overrides) |override| if (std.mem.eql(u8, override.source, record.source)) {
            target = override.target;
            break;
        };
        if (std.mem.endsWith(u8, record.source, ".weiv")) {
            const spec = if (target) |value| try allocator.dupe(u8, value) else try common.emittedDirectImportSpecifier(record.source, allocator);
            defer allocator.free(spec);
            try out.print(allocator, "import * as {s} from \"{s}\";\n", .{ record.local_name, spec });
            continue;
        }
        const spec = if (target) |value| try allocator.dupe(u8, value) else try common.emittedRuntimeImportSpecifier(record.source, allocator);
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
