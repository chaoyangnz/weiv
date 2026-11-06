const std = @import("std");
const browser_component = @import("../component.zig");
const runtime_prelude = @import("js_module/runtime_prelude.zig");
const structural_codegen = @import("js_module/structural_codegen.zig");
const dom_create = @import("js_module/dom_create.zig");
const dom_update = @import("js_module/dom_update.zig");
const dom_destroy = @import("js_module/dom_destroy.zig");
const tracked_metadata = @import("js_module/tracked_metadata.zig");
const region_graph = @import("../region_graph.zig");
const setup = @import("js_module/setup.zig");
const scoped_css = @import("scoped_css.zig");
pub const ManagedSubscription = struct { specifier: []const u8, name: []const u8, binding: []const u8 };
pub const ImportOverride = struct { source: []const u8, target: []const u8 };
pub const LocalSubscription = struct { name: []const u8, binding: []const u8, publisher_backed: bool = false };

pub fn collectCellDiagnostics(component: *const browser_component.BrowserComponent, selected: ?[]const []const u8, bag: *@import("../../../diagnostics.zig").DiagnosticBag, allocator: std.mem.Allocator) !void {
    const state = @import("../../../project/state_dependencies.zig");
    var plan = state.ManagedPlan{};
    defer plan.deinit(allocator);
    var inferred = std.ArrayList([]const u8).empty;
    defer inferred.deinit(allocator);
    if (selected == null) {
        const entries = try state.analyzeManaged(component.unit, null, &plan, allocator);
        defer {
            for (entries) |*entry| entry.deinit(allocator);
            allocator.free(entries);
        }
        for (plan.locals.items) |local| try inferred.append(allocator, local.name);
    }
    const names = try setup.buildCellNames(component.unit, selected orelse inferred.items, allocator);
    defer allocator.free(names);
    try @import("../../../project/cell_diagnostics.zig").inspect(component.unit, names, bag, allocator);
}

pub fn emitModule(component: *const browser_component.BrowserComponent, allocator: std.mem.Allocator) ![]u8 {
    return emitModuleWithCells(component, true, allocator);
}

pub fn emitModuleWithCells(component: *const browser_component.BrowserComponent, cells: bool, allocator: std.mem.Allocator) ![]u8 {
    if (!cells) return emitModuleWithSubscriptions(component, false, &.{}, allocator);
    const state = @import("../../../project/state_dependencies.zig");
    var plan = state.ManagedPlan{};
    defer plan.deinit(allocator);
    const entries = try state.analyzeManaged(component.unit, null, &plan, allocator);
    defer {
        for (entries) |*entry| entry.deinit(allocator);
        allocator.free(entries);
    }
    var names = std.ArrayList([]const u8).empty;
    defer names.deinit(allocator);
    for (plan.locals.items) |local| try names.append(allocator, local.name);
    var local_subscriptions = std.ArrayList(LocalSubscription).empty;
    defer local_subscriptions.deinit(allocator);
    for (plan.local_subscriptions.items) |item| try local_subscriptions.append(allocator, .{ .name = item.name, .binding = item.binding, .publisher_backed = item.publisher_backed });
    return emitModuleWithSelection(component, true, &.{}, &.{}, names.items, local_subscriptions.items, allocator);
}

pub fn emitModuleWithSubscriptions(component: *const browser_component.BrowserComponent, cells: bool, subscriptions: []const ManagedSubscription, allocator: std.mem.Allocator) ![]u8 {
    return emitModuleWithImports(component, cells, subscriptions, &.{}, allocator);
}

pub fn emitModuleWithImports(component: *const browser_component.BrowserComponent, cells: bool, subscriptions: []const ManagedSubscription, overrides: []const ImportOverride, allocator: std.mem.Allocator) ![]u8 {
    return emitModuleWithSelection(component, cells, subscriptions, overrides, null, &.{}, allocator);
}

pub fn emitModuleWithSelection(component: *const browser_component.BrowserComponent, cells: bool, subscriptions: []const ManagedSubscription, overrides: []const ImportOverride, local_names: ?[]const []const u8, local_subscriptions: []const LocalSubscription, allocator: std.mem.Allocator) ![]u8 {
    const model = component.unit;
    var expression_arena = std.heap.ArenaAllocator.init(allocator);
    defer expression_arena.deinit();
    var expressions = @import("js_module/cell_expressions.zig").Plan{ .allocator = expression_arena.allocator(), .script_names = try @import("../../../project/template_functions.zig").bindingNames(&model.script, expression_arena.allocator()) };
    var render_tree = component.render_tree;
    if (cells) render_tree.nodes = try expressions.nodes(component.render_tree.nodes);
    const scope_id = try scoped_css.scopeIdForPath(model.source_path, allocator);
    defer allocator.free(scope_id);
    const css = try scoped_css.emitScopedCss(model, allocator);
    defer allocator.free(css);
    const setup_js = try setup.buildSetupCodeWithExpressions(model, cells, subscriptions, local_names, local_subscriptions, expressions.evaluators.items, allocator);
    defer allocator.free(setup_js);
    const preserved_imports = try setup.buildPreservedImportsWithOverrides(model, overrides, allocator);
    defer allocator.free(preserved_imports);
    const template_bindings_json = try setup.buildTemplateBindingsJson(model, allocator);
    defer allocator.free(template_bindings_json);
    var body = std.ArrayList(u8).empty;
    defer body.deinit(allocator);

    try structural_codegen.emitStructuralHelpers(render_tree.nodes, scope_id, template_bindings_json, &body, allocator);
    try body.appendSlice(allocator, setup_js);
    try body.appendSlice(allocator, "\n");
    try body.print(allocator, "export const scopeId = \"{s}\";\n", .{scope_id});
    try body.appendSlice(allocator, "export const css = ");
    try @import("js_module/common.zig").emitString(css, &body, allocator);
    try body.appendSlice(allocator, ";\n\n");

    var runtime_graph = try region_graph.buildWithCells(model, &component.render_tree, cells, allocator);
    defer runtime_graph.deinit();
    try tracked_metadata.emitTrackedStateGraphMetadata(&runtime_graph, &body, allocator);
    try body.appendSlice(allocator, "\n");
    try dom_create.emitCreateFunction(render_tree, scope_id, &body, allocator);
    try body.appendSlice(allocator, "\n");
    try dom_update.emitRegionUpdateFunctions(render_tree, template_bindings_json, &body, allocator);
    try body.appendSlice(allocator, "\n");
    try dom_update.emitUpdateFunction(render_tree, &body, allocator);
    try body.appendSlice(allocator, "\n");
    try dom_update.emitSelectiveUpdateFunction(&runtime_graph, render_tree, &body, allocator);
    try body.appendSlice(allocator, "\n");
    try dom_destroy.emitDestroyFunction(render_tree, &body, allocator);
    try body.appendSlice(allocator,
        \\
        \\export function createInstance(props = {}, eventHandlers = {}, slots = {}) {
        \\  const base = setup(props, eventHandlers);
        \\  const instance = {
        \\    cellManaged: __weiv_cellManaged,
        \\    scope: base.scope,
        \\    refresh: base.refresh,
        \\    setProps: base.setProps,
        \\    setEventHandlers: base.setEventHandlers,
        \\    setBoundaryRunner: base.setBoundaryRunner,
        \\    subscribeImportedObservables: base.subscribeImportedObservables,
        \\    slots,
        \\    setSlots: (nextSlots = {}) => { instance.slots = nextSlots; },
        \\    refs: [],
        \\    destroyed: false,
        \\    update: () => {},
        \\    updateDirty: () => {},
        \\    destroy: () => {},
        \\  };
        \\  instance.setBoundaryRunner((callback) => runOwnedBoundary(instance, callback));
        \\  __weiv_registerTrackedSubscriber(instance);
        \\  return instance;
        \\}
        \\
        \\export function mountIntoBoundary(start, end, props = {}, eventHandlers = {}, slots = {}) {
        \\  const instance = createInstance(props, eventHandlers, slots);
        \\  instance.setSlots = (nextSlots = {}) => { instance.slots = nextSlots; };
        \\  const fragment = createDom(instance);
        \\  replaceBetween(start, end, fragment);
        \\  instance.update = () => updateDom(instance);
        \\  instance.updateDirty = (dirtyBindings, scope) => updateDirtyRegions(instance, dirtyBindings, scope);
        \\  const __weiv_unsubscribeImportedObservables = typeof instance.subscribeImportedObservables === "function"
        \\    ? instance.subscribeImportedObservables(instance)
        \\    : null;
        \\  instance.destroy = () => { if (typeof __weiv_unsubscribeImportedObservables === "function") __weiv_unsubscribeImportedObservables(); __weiv_unregisterTrackedSubscriber(instance); instance.destroyed = true; destroyDom(instance); replaceBetween(start, end, document.createDocumentFragment()); };
        \\  instance.update();
        \\  return {
        \\    instance,
        \\    update: instance.update,
        \\    destroy: instance.destroy,
        \\    setProps: instance.setProps,
        \\    setEventHandlers: instance.setEventHandlers,
        \\    setSlots: instance.setSlots,
        \\    start,
        \\    end,
        \\  };
        \\}
        \\
        \\export function mount(target, props = {}, eventHandlers = {}, slots = {}) {
        \\  const start = document.createComment("root:start");
        \\  const end = document.createComment("root:end");
        \\  target.replaceChildren(start, end);
        \\  return mountIntoBoundary(start, end, props, eventHandlers, slots);
        \\}
        \\
    );

    var out = std.ArrayList(u8).empty;
    defer out.deinit(allocator);
    if (cells) try out.appendSlice(allocator, "import { createCell as __weiv_createCell, createCellScope as __weiv_createCellScope, unbindCellValue as __weiv_unbindCellValue, normalizeCellValue as __weiv_normalizeCellValue, cellAssignmentTarget as __weiv_cellAssignmentTarget, bindingObject as __weiv_bindingObject, bindingIterator as __weiv_bindingIterator, initializeClassName as __weiv_initializeClassName } from \"weiv:cells\";\n");
    for (subscriptions, 0..) |subscription, index| {
        try out.print(allocator, "import {{ moduleState as __weiv_publisher_{d} }} from ", .{index});
        try @import("js_module/common.zig").emitString(subscription.specifier, &out, allocator);
        try out.appendSlice(allocator, ";\n");
    }
    try out.print(allocator, "const __weiv_cellManaged = {s};\n", .{if (cells) "true" else "false"});
    try out.appendSlice(allocator, preserved_imports);
    try runtime_prelude.emitPrelude(&out, allocator);
    try out.appendSlice(allocator, body.items);

    return try out.toOwnedSlice(allocator);
}
