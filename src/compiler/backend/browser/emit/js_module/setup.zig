const imports = @import("imports.zig");
const std = @import("std");
const component = @import("../../../../component_unit.zig");
const tracked_roots = @import("../../tracked_roots.zig");
const js_output = @import("output.zig");

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
        try js_output.emitString(binding.name, &names, allocator);
    }
    try names.append(allocator, ']');
    return names.toOwnedSlice(allocator);
}

pub fn buildSetupCodeWithExpressions(model: *const component.ComponentUnit, subscriptions: []const @import("../js_module.zig").ManagedSubscription, local_names: ?[]const []const u8, local_subscriptions: []const @import("../js_module.zig").LocalSubscription, expressions: []const u8, allocator: std.mem.Allocator) ![]u8 {
    var out = std.ArrayList(u8).empty;
    defer out.deinit(allocator);

    try out.appendSlice(allocator,
        \\function setup(__weiv_props, __weiv_event_handlers = {}) {
        \\  const __weiv_propsCell = __weiv_createCell(__weiv_props);
        \\  let props = __weiv_propsCell.value;
        \\  let __weiv_handlers = __weiv_event_handlers;
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

    const cell_names = try buildCellNames(model, local_names, allocator);
    defer allocator.free(cell_names);
    const lowered_script = try @import("../../../../../ffi/script_backend.zig").lowerCellsWithExpressions(model.sfc_document.script.content, model.source_path, cell_names, expressions, allocator);
    defer allocator.free(lowered_script);
    try out.appendSlice(allocator, lowered_script);
    try out.appendSlice(allocator, "\n");

    try out.appendSlice(allocator, "  const __weiv_scope = {__proto__: null};\n");
    if (expressions.len > 0) try out.appendSlice(allocator, "  __weiv_scope.__weiv_eval = __weiv_templateExpressions;\n");
    try out.appendSlice(allocator, "  function __weiv_refresh() {\n");
    try out.appendSlice(allocator, "    __weiv_scope.props = props;\n");
    try out.appendSlice(allocator, "    __weiv_scope.emit = emit;\n");
    for (model.script.imports) |import_record| {
        if (import_record.local_name.len == 0) continue;
        if (std.mem.endsWith(u8, import_record.source, ".weiv")) continue;
        if (!imports.shouldPreserveImport(import_record, &model.script)) continue;
        try out.print(allocator, "    __weiv_scope.{s} = {s}{s};\n", .{ import_record.local_name, "__weiv_import_", import_record.local_name });
    }
    for (model.script.bindings) |binding| {
        if (binding.template_visible and !std.mem.eql(u8, binding.kind, "import")) {
            try out.print(allocator, "    __weiv_scope.{s} = {s}{s};\n", .{ binding.name, binding.name, if (selectedCellBinding(model, binding, local_names)) ".value" else "" });
        }
    }
    try out.appendSlice(allocator, "    return __weiv_scope;\n");
    try out.appendSlice(allocator, "  }\n");
    try out.appendSlice(allocator, "  function __weiv_setProps(nextProps) {\n");
    try out.appendSlice(allocator, "    __weiv_propsCell.value = nextProps;\n    props = __weiv_propsCell.value;\n");
    try out.appendSlice(allocator, "  }\n");
    try out.appendSlice(allocator, "  function __weiv_setEventHandlers(nextHandlers) {\n    __weiv_handlers = nextHandlers;\n  }\n");
    try out.appendSlice(allocator, "  function __weiv_subscribeImportedObservables(__weiv_instance) {\n");
    {
        try out.appendSlice(allocator, "    const __weiv_cellScope = __weiv_createCellScope((dirty) => { if (!__weiv_instance.destroyed) __weiv_instance.updateDirty({ bindings: [...dirty], paths: [] }, __weiv_instance.refresh()); });\n");
        try out.appendSlice(allocator, "    __weiv_cellScope.watch(__weiv_propsCell, \"props\");\n");
        for (model.script.bindings) |binding| {
            if (local_names == null and selectedCellBinding(model, binding, local_names)) try out.print(allocator, "    __weiv_cellScope.watch({s}, \"{s}\");\n", .{ binding.name, binding.name });
        }
        for (local_subscriptions) |subscription| {
            for (model.script.bindings) |binding| {
                if (!std.mem.eql(u8, binding.name, subscription.name) or !selectedCellBinding(model, binding, local_names)) continue;
                try out.print(allocator, "    __weiv_cellScope.watch({s}, ", .{subscription.name});
                try js_output.emitString(subscription.binding, &out, allocator);
                try out.appendSlice(allocator, ");\n");
            }
        }
        for (subscriptions, 0..) |subscription, index| {
            try out.print(allocator, "    __weiv_cellScope.watch(__weiv_publisher_{d}.getCell(", .{index});
            try js_output.emitString(subscription.name, &out, allocator);
            try out.appendSlice(allocator, "), ");
            try js_output.emitString(subscription.binding, &out, allocator);
            try out.appendSlice(allocator, ");\n");
        }
        imports: for (model.script.imports) |record| {
            if (record.local_name.len == 0 or !imports.shouldPreserveImport(record, &model.script)) continue;
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
                try js_output.emitString(record.local_name, &out, allocator);
                try out.appendSlice(allocator, ");\n");
            }
            for (local_subscriptions) |subscription| {
                if (!std.mem.eql(u8, subscription.name, record.local_name)) continue;
                try out.appendSlice(allocator, "      __weiv_cellScope.watch(__weiv_importedCell, ");
                try js_output.emitString(subscription.binding, &out, allocator);
                try out.appendSlice(allocator, ");\n");
            }
            try out.appendSlice(allocator, "    }\n");
        }
        try out.appendSlice(allocator, "    return () => __weiv_cellScope.dispose();\n");
    }
    try out.appendSlice(allocator, "  }\n");
    try out.appendSlice(allocator, "  return { scope: __weiv_scope, refresh: __weiv_refresh, setProps: __weiv_setProps, setEventHandlers: __weiv_setEventHandlers, subscribeImportedObservables: __weiv_subscribeImportedObservables };\n}\n");

    return try out.toOwnedSlice(allocator);
}
