const std = @import("std");
const browser_backend = @import("compiler/backend/browser/index.zig");
const compiler_compile = @import("compiler/compile.zig");
const compiler_diagnostics = @import("compiler/diagnostics.zig");
const component = @import("compiler/component_unit.zig");
const inspect = @import("compiler/inspect/index.zig");
const lower = @import("compiler/lower/index.zig");
const parser = @import("compiler/parser/index.zig");
const cli = @import("cli.zig");

const app_emit = browser_backend.emit.app;
const ast = parser.template.ast;
const browser_component = browser_backend.component;
const browser_render_tree = browser_backend.render_tree;
const browser_region_graph = @import("compiler/backend/browser/region_graph.zig");
const directives = parser.template.directives;
const js_module = browser_backend.emit.js_module;
const invalidation_graph = inspect.invalidation_graph;
const sfc = parser.sfc;
const style = browser_backend.emit.scoped_css;

fn emitComponentJs(model: *const component.ComponentUnit, allocator: std.mem.Allocator) ![]u8 {
    var browser_component_model = try browser_component.build(model, allocator);
    defer browser_component_model.deinit(allocator);
    return try js_module.emitModuleWithCells(&browser_component_model, false, allocator);
}

test "Atelier immutable local binding remains valid after tracked-root setup" {
    const allocator = std.testing.allocator;
    const source =
        \\<template><p>{{ projectKey }}</p></template>
        \\<script lang="ts">const projectKey = "atelier.projects.v1";</script>
    ;
    var model = try compiler_compile.compile(source, "atelier-const.weiv", allocator);
    defer model.deinit(allocator);
    const js = try emitComponentJs(&model, allocator);
    defer allocator.free(js);
    try std.testing.expect(std.mem.indexOf(u8, js, "let projectKey = \"atelier.projects.v1\";") != null);
    try std.testing.expect(std.mem.indexOf(u8, js, "projectKey = __weiv_getTrackedRoot(\"projectKey\", projectKey);") != null);
}

test "Atelier imported function is initialized before top-level registration" {
    const allocator = std.testing.allocator;
    const source =
        \\<template><p>ready</p></template>
        \\<script lang="ts">
        \\import { listen } from "./event.ts";
        \\listen("run-event", () => {});
        \\</script>
    ;
    var model = try compiler_compile.compile(source, "atelier-import-order.weiv", allocator);
    defer model.deinit(allocator);
    const js = try emitComponentJs(&model, allocator);
    defer allocator.free(js);
    const initialized = std.mem.indexOf(u8, js, "const listen = __weiv_getTrackedRoot(\"listen\", __weiv_import_listen);") orelse return error.MissingImportInitialization;
    const registration = std.mem.indexOf(u8, js, "listen(\"run-event\", () => {});") orelse return error.MissingListenerRegistration;
    try std.testing.expect(initialized < registration);
}

test "type-only imports are absent from runtime setup" {
    const allocator = std.testing.allocator;
    const source =
        \\<template><p>{{ label }}</p></template>
        \\<script lang="ts">
        \\import type { Standalone } from "./types.ts";
        \\import { format, type Inline } from "./format.ts";
        \\let label: Standalone | Inline = format("ready");
        \\</script>
    ;
    var model = try compiler_compile.compile(source, "type-imports.weiv", allocator);
    defer model.deinit(allocator);
    const js = try emitComponentJs(&model, allocator);
    defer allocator.free(js);
    try std.testing.expect(std.mem.indexOf(u8, js, "__weiv_import_Standalone") == null);
    try std.testing.expect(std.mem.indexOf(u8, js, "__weiv_import_Inline") == null);
    try std.testing.expect(std.mem.indexOf(u8, js, "__weiv_scope.Standalone") == null);
    try std.testing.expect(std.mem.indexOf(u8, js, "__weiv_scope.Inline") == null);
    try std.testing.expect(std.mem.indexOf(u8, js, "__weiv_register(\"Standalone\"") == null);
    try std.testing.expect(std.mem.indexOf(u8, js, "__weiv_register(\"Inline\"") == null);
    try std.testing.expect(std.mem.indexOf(u8, js, "__weiv_import_format") != null);
}

test "Atelier compound loop expression resolves both item and component helper" {
    const allocator = std.testing.allocator;
    const source =
        \\<template><article #for="message in messages">{{ message.role === 'user' ? 'You' : engineName() }}</article></template>
        \\<script lang="ts">
        \\let messages = [{ role: "assistant" }];
        \\function engineName() { return "Codex"; }
        \\</script>
    ;
    var model = try compiler_compile.compile(source, "atelier-compound.weiv", allocator);
    defer model.deinit(allocator);
    const js = try emitComponentJs(&model, allocator);
    defer allocator.free(js);
    try std.testing.expect(std.mem.indexOf(u8, js, "scope.message.role === 'user' ? 'You' : scope.engineName()") != null);
}

test "malformed TypeScript halts with a syntax location" {
    const allocator = std.testing.allocator;
    const source =
        \\<template><button @click="click">Go</button></template>
        \\<script lang="ts">let id = "a"; let rows: any[] = []; function click() { rows.some((row: any) => row.id === id; }</script>
    ;
    var report = try compiler_compile.compileReport(source, "malformed-script.weiv", allocator);
    defer report.deinit(allocator);
    try std.testing.expectEqual(@as(?compiler_diagnostics.Stage, .script_facts), report.halted_after);
    try std.testing.expect(report.halt_error != null);
    try std.testing.expect(report.diagnostics.len > 0);
    try std.testing.expect(report.diagnostics[0].fatal);
    try std.testing.expectEqualStrings("script.syntax", report.diagnostics[0].code);
    try std.testing.expect(report.diagnostics[0].location != null);
    try std.testing.expect(report.diagnostics[0].location.?.column > 1);
}

test "template dependency analysis uses bound expression references" {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const source =
        \\<template>
        \\  <p>{{ "count" }}</p>
        \\  <p>{{ state . count }}</p>
        \\</template>
        \\<script lang="ts">
        \\  let state = { count: 1 };
        \\</script>
    ;

    const input = try allocator.dupe(u8, source);
    var model = try compiler_compile.compile(input, "inline-bound-expressions.weiv", allocator);
    allocator.free(input);
    defer model.deinit(allocator);
    var tree = try browser_render_tree.lower(&model.lir_document, allocator);
    defer tree.deinit(allocator);
    var graph = try browser_region_graph.build(&model, &tree, allocator);
    defer graph.deinit();

    try std.testing.expectEqual(@as(usize, 2), graph.regions.items.len);
    try std.testing.expectEqual(@as(usize, 0), graph.regions.items[0].dependency_names.items.len);
    try std.testing.expectEqualSlices(u8, "state", graph.regions.items[1].dependency_names.items[0]);
    try std.testing.expectEqual(@as(usize, 1), graph.regions.items[1].dependency_names.items.len);
}

test "classic todo app components build through current component pipeline" {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    try expectComponentBuild(
        allocator,
        try readFixture(allocator, "test/examples/classic-todo/App.weiv"),
        "test/examples/classic-todo/App.weiv",
        1,
        0,
    );
    try expectComponentBuild(
        allocator,
        try readFixture(allocator, "test/examples/classic-todo/TodoList.weiv"),
        "test/examples/classic-todo/TodoList.weiv",
        1,
        0,
    );
    try expectComponentBuild(
        allocator,
        try readFixture(allocator, "test/examples/classic-todo/TodoItem.weiv"),
        "test/examples/classic-todo/TodoItem.weiv",
        0,
        0,
    );
}

test "todomvc verification app components build through current component pipeline" {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    try expectComponentBuild(
        allocator,
        try readFixture(allocator, "test/examples/todomvc/App.weiv"),
        "test/examples/todomvc/App.weiv",
        3,
        0,
    );
    try expectComponentBuild(
        allocator,
        try readFixture(allocator, "test/examples/todomvc/TodoHeader.weiv"),
        "test/examples/todomvc/TodoHeader.weiv",
        1,
        0,
    );
    try expectComponentBuild(
        allocator,
        try readFixture(allocator, "test/examples/todomvc/TodoFooter.weiv"),
        "test/examples/todomvc/TodoFooter.weiv",
        0,
        0,
    );
    try expectComponentBuild(
        allocator,
        try readFixture(allocator, "test/examples/todomvc/TodoList.weiv"),
        "test/examples/todomvc/TodoList.weiv",
        1,
        0,
    );
    try expectComponentBuild(
        allocator,
        try readFixture(allocator, "test/examples/todomvc/TodoItem.weiv"),
        "test/examples/todomvc/TodoItem.weiv",
        1,
        0,
    );
    try expectComponentBuild(
        allocator,
        try readFixture(allocator, "test/examples/todomvc/TodoTextInput.weiv"),
        "test/examples/todomvc/TodoTextInput.weiv",
        0,
        0,
    );
}

test "kanib app components build through current component pipeline" {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    try expectComponentBuild(
        allocator,
        try readFixture(allocator, "test/examples/kanib/App.weiv"),
        "test/examples/kanib/App.weiv",
        4,
        4,
    );
    try expectComponentBuild(
        allocator,
        try readFixture(allocator, "test/examples/kanib/components/WorkspaceShell.weiv"),
        "test/examples/kanib/components/WorkspaceShell.weiv",
        0,
        0,
    );
    try expectComponentBuild(
        allocator,
        try readFixture(allocator, "test/examples/kanib/components/WorkspaceHeader.weiv"),
        "test/examples/kanib/components/WorkspaceHeader.weiv",
        0,
        0,
    );
    try expectComponentBuild(
        allocator,
        try readFixture(allocator, "test/examples/kanib/components/WorkspaceSidebar.weiv"),
        "test/examples/kanib/components/WorkspaceSidebar.weiv",
        0,
        2,
    );
    try expectComponentBuild(
        allocator,
        try readFixture(allocator, "test/examples/kanib/views/OverviewPage.weiv"),
        "test/examples/kanib/views/OverviewPage.weiv",
        3,
        0,
    );
    try expectComponentBuild(
        allocator,
        try readFixture(allocator, "test/examples/kanib/components/MetricGrid.weiv"),
        "test/examples/kanib/components/MetricGrid.weiv",
        1,
        0,
    );
    try expectComponentBuild(
        allocator,
        try readFixture(allocator, "test/examples/kanib/views/IssueListPage.weiv"),
        "test/examples/kanib/views/IssueListPage.weiv",
        3,
        0,
    );
    try expectComponentBuild(
        allocator,
        try readFixture(allocator, "test/examples/kanib/components/DetailPanel.weiv"),
        "test/examples/kanib/components/DetailPanel.weiv",
        4,
        0,
    );
    try expectComponentBuild(
        allocator,
        try readFixture(allocator, "test/examples/kanib/views/IssueDetailPage.weiv"),
        "test/examples/kanib/views/IssueDetailPage.weiv",
        6,
        0,
    );
    try expectComponentBuild(
        allocator,
        try readFixture(allocator, "test/examples/kanib/components/Panel.weiv"),
        "test/examples/kanib/components/Panel.weiv",
        0,
        0,
    );
    try expectComponentBuild(
        allocator,
        try readFixture(allocator, "test/examples/kanib/components/EmptyState.weiv"),
        "test/examples/kanib/components/EmptyState.weiv",
        0,
        0,
    );
}

test "classic todo app app component lowers to expected LIR shape" {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const source = try readFixture(allocator, "test/examples/classic-todo/App.weiv");
    defer allocator.free(source);

    var model = try compiler_compile.compile(source, "test/examples/classic-todo/App.weiv", allocator);
    defer model.deinit(allocator);

    try std.testing.expectEqual(@as(usize, 1), model.lir_document.nodes.len);

    switch (model.lir_document.nodes[0]) {
        .element => |root| {
            try std.testing.expect(std.mem.eql(u8, root.tag_name, "main"));
            try std.testing.expectEqual(@as(usize, 1), root.children.len);

            switch (root.children[0]) {
                .element => |shell| {
                    try std.testing.expect(std.mem.eql(u8, shell.tag_name, "div"));
                    try std.testing.expectEqual(@as(usize, 2), shell.children.len);

                    switch (shell.children[1]) {
                        .element => |panel| {
                            try std.testing.expect(std.mem.eql(u8, panel.tag_name, "section"));
                            try std.testing.expectEqual(@as(usize, 2), panel.children.len);

                            switch (panel.children[1]) {
                                .component => |child| {
                                    try std.testing.expect(std.mem.eql(u8, child.tag_name, "TodoList"));
                                    try std.testing.expectEqual(@as(usize, 3), child.effects.len);
                                },
                                else => return error.UnexpectedIrShape,
                            }
                        },
                        else => return error.UnexpectedIrShape,
                    }
                },
                else => return error.UnexpectedIrShape,
            }
        },
        else => return error.UnexpectedIrShape,
    }
}

test "basic counter direct browser module emits create/update DOM contract" {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const source = try readFixture(allocator, "test/examples/basic/basic-counter.weiv");
    defer allocator.free(source);

    var model = try compiler_compile.compile(source, "test/examples/basic/basic-counter.weiv", allocator);
    defer model.deinit(allocator);

    const js = try emitComponentJs(&model, allocator);
    defer allocator.free(js);

    try std.testing.expect(std.mem.indexOf(u8, js, "function createDom(instance)") != null);
    try std.testing.expect(std.mem.indexOf(u8, js, "function updateDom(instance)") != null);
    try std.testing.expect(std.mem.indexOf(u8, js, "function updateRegion_text_") != null);
    try std.testing.expect(std.mem.indexOf(u8, js, "function updateRegion_attribute_") != null);
    try std.testing.expect(std.mem.indexOf(u8, js, "updateRegion_text_") != null);
    try std.testing.expect(std.mem.indexOf(u8, js, "updateRegion_attribute_") != null);
    try std.testing.expect(std.mem.indexOf(u8, js, "function runOwnedBoundary(instance, callback)") != null);
    try std.testing.expect(std.mem.indexOf(u8, js, "document.createElement(\"section\")") != null);
    try std.testing.expect(std.mem.indexOf(u8, js, "addEventListener(\"click\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, js, "addEventListener(\"click\", (event) => runOwnedBoundary(instance, () => {") != null);
    try std.testing.expect(std.mem.indexOf(u8, js, "return resolved(event);") != null);
    try std.testing.expect(std.mem.indexOf(u8, js, "function collectDirtyBindings(beforeScope, afterScope)") != null);
    try std.testing.expect(std.mem.indexOf(u8, js, "const dirtyBindings = collectDirtyBindings(beforeScope, afterScope);") != null);
    try std.testing.expect(std.mem.indexOf(u8, js, "function normalizeDirtyState(dirtyState)") != null);
    try std.testing.expect(std.mem.indexOf(u8, js, "const __weiv_observableBrand = Symbol.for(\"weiv.observable\");") != null);
    try std.testing.expect(std.mem.indexOf(u8, js, "function __weiv_getObservableNode(value)") != null);
    try std.testing.expect(std.mem.indexOf(u8, js, "function __weiv_isObservable(value)") != null);
    try std.testing.expect(std.mem.indexOf(u8, js, "function __weiv_getTrackedRoot(bindingName, value)") != null);
    try std.testing.expect(std.mem.indexOf(u8, js, "if (__weiv_isObservable(value)) {") != null);
    try std.testing.expect(std.mem.indexOf(u8, js, "function collectTrackedDirtyPaths()") != null);
    try std.testing.expect(std.mem.indexOf(u8, js, "function updateDirtyRegions(instance, dirtyState, scope = instance.refresh())") != null);
    try std.testing.expect(std.mem.indexOf(u8, js, "const normalizedDirtyState = normalizeDirtyState(dirtyState);") != null);
    try std.testing.expect(std.mem.indexOf(u8, js, "const dirtySet = new Set(normalizedDirtyState.bindings);") != null);
    try std.testing.expect(std.mem.indexOf(u8, js, "const dirtyPathSet = new Set(normalizedDirtyState.paths);") != null);
    try std.testing.expect(std.mem.indexOf(u8, js, "const dirtyRegionSet = new Set();") != null);
    try std.testing.expect(std.mem.indexOf(u8, js, "instance.updateDirty({ bindings: dirtyBindings, paths: dirtyPaths }, afterScope);") != null);
    try std.testing.expect(std.mem.indexOf(u8, js, "__weiv_registerTrackedSubscriber(instance);") != null);
    try std.testing.expect(std.mem.indexOf(u8, js, "__weiv_unregisterTrackedSubscriber(instance);") != null);
    try std.testing.expect(std.mem.indexOf(u8, js, "function __weiv_subscribeImportedObservables(instance)") != null);
    try std.testing.expect(std.mem.indexOf(u8, js, "subscribeImportedObservables: __weiv_subscribeImportedObservables") != null);
    try std.testing.expect(std.mem.indexOf(u8, js, "instance.updateDirty = (dirtyBindings, scope) => updateDirtyRegions(instance, dirtyBindings, scope);") != null);
    try std.testing.expect(std.mem.indexOf(u8, js, "if (dirtySet.has(\"count\") || dirtySet.has(\"limit\") || dirtyRegionSet.has(4)) {") != null);
    try std.testing.expect(std.mem.indexOf(u8, js, "if (dirtySet.has(\"doubled\") || dirtySet.has(\"count\") || dirtyRegionSet.has(3)) {") != null);
    try std.testing.expect(std.mem.indexOf(u8, js, "const resolved = instance.refresh().increment;") != null);
    try std.testing.expect(std.mem.indexOf(u8, js, "const __next_text_0 = String((scope.props.title) ?? \"\");") != null);
    try std.testing.expect(std.mem.indexOf(u8, js, "const __next_text_2 = String((scope.count) ?? \"\");") != null);
    try std.testing.expect(std.mem.indexOf(u8, js, "function evaluate(") == null);
    try std.testing.expect(std.mem.indexOf(u8, js, "evaluate(") == null);
    try std.testing.expect(std.mem.indexOf(u8, js, "refs[") != null);
    try std.testing.expect(std.mem.indexOf(u8, js, "const __next_text_") != null);
    try std.testing.expect(std.mem.indexOf(u8, js, ".data !== __next_text_") != null);
}

test "direct browser modules compile simple callback-argument expressions directly" {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const source =
        \\<template>
        \\  <p>{{ items.filter((item) => item.done).length }}</p>
        \\</template>
        \\
        \\<script lang="ts">
        \\  export interface Props {}
        \\  export let props: Props;
        \\  let items = [{ done: true }, { done: false }];
        \\</script>
    ;

    var model = try compiler_compile.compile(source, "inline-evaluate-fallback.weiv", allocator);
    defer model.deinit(allocator);

    const js = try emitComponentJs(&model, allocator);
    defer allocator.free(js);

    try std.testing.expect(std.mem.indexOf(u8, js, "function evaluate(") == null);
    try std.testing.expect(std.mem.indexOf(u8, js, "scope.items.filter((item) => item.done).length") != null);
    try std.testing.expect(std.mem.indexOf(u8, js, "evaluate(\"items.filter((item) => item.done).length\", scope)") == null);
}

test "loop event call expressions compile without unsafe eval and inside owned boundaries" {
    const allocator = std.testing.allocator;
    const source = try readFixture(allocator, "test/examples/basic/nested-conditional-list.weiv");
    defer allocator.free(source);

    var model = try compiler_compile.compile(source, "test/examples/basic/nested-conditional-list.weiv", allocator);
    defer model.deinit(allocator);

    const js = try emitComponentJs(&model, allocator);
    defer allocator.free(js);

    try std.testing.expect(std.mem.indexOf(u8, js, "Function(...names") == null);
    try std.testing.expect(std.mem.indexOf(u8, js, "__weiv_evaluate(") == null);
    try std.testing.expect(std.mem.indexOf(u8, js, "addEventListener(\"click\", (event) => runOwnedBoundary(instance, () => {") != null);
    try std.testing.expect(std.mem.indexOf(u8, js, "const resolved = loopScope.selectStrategy(loopScope.strategy.id);") != null);
    try std.testing.expect(std.mem.indexOf(u8, js, ".style.cssText = \"display: block\";") != null);
    try std.testing.expect(std.mem.indexOf(u8, js, ".style.cssText = __value_") != null);
    try std.testing.expect(std.mem.indexOf(u8, js, ".setAttribute(\"style\"") == null);
}

test "component async helpers retain owned boundaries when their promises are discarded" {
    const allocator = std.testing.allocator;
    const source = try readFixture(allocator, "test/examples/basic/framecept-reactivity.weiv");
    defer allocator.free(source);

    var model = try compiler_compile.compile(source, "test/examples/basic/framecept-reactivity.weiv", allocator);
    defer model.deinit(allocator);

    const js = try emitComponentJs(&model, allocator);
    defer allocator.free(js);

    try std.testing.expect(std.mem.indexOf(u8, js, "loadMissingThumbnails = __weiv_wrapCallback(loadMissingThumbnails);") != null);
    try std.testing.expect(std.mem.indexOf(u8, js, "startThumbnailLoad = __weiv_wrapCallback(startThumbnailLoad);") == null);
}

test "direct browser modules compile block-bodied callback-argument expressions directly" {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const source =
        \\<template>
        \\  <p>{{ items.filter((item) => { return item.done; }).length }}</p>
        \\</template>
        \\
        \\<script lang="ts">
        \\  export interface Props {}
        \\  export let props: Props;
        \\  let items = [{ done: true }, { done: false }];
        \\</script>
    ;

    var model = try compiler_compile.compile(source, "inline-block-callback-evaluate-fallback.weiv", allocator);
    defer model.deinit(allocator);

    const js = try emitComponentJs(&model, allocator);
    defer allocator.free(js);

    try std.testing.expect(std.mem.indexOf(u8, js, "function evaluate(") == null);
    try std.testing.expect(std.mem.indexOf(u8, js, "scope.items.filter((item) => { return item.done; }).length") != null);
    try std.testing.expect(std.mem.indexOf(u8, js, "evaluate(\"items.filter((item) => { return item.done; }).length\", scope)") == null);
}

test "direct browser modules compile bracket-access expressions directly" {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const source =
        \\<template>
        \\  <p>{{ items[selectedIndex].title }}</p>
        \\</template>
        \\
        \\<script lang="ts">
        \\  export interface Props {}
        \\  export let props: Props;
        \\  let selectedIndex = 0;
        \\  let items = [{ title: "One" }, { title: "Two" }];
        \\</script>
    ;

    var model = try compiler_compile.compile(source, "inline-bracket-access.weiv", allocator);
    defer model.deinit(allocator);

    const js = try emitComponentJs(&model, allocator);
    defer allocator.free(js);

    try std.testing.expect(std.mem.indexOf(u8, js, "function evaluate(") == null);
    try std.testing.expect(std.mem.indexOf(u8, js, "scope.items[scope.selectedIndex].title") != null);
    try std.testing.expect(std.mem.indexOf(u8, js, "evaluate(\"items[selectedIndex].title\", scope)") == null);
}

test "direct browser module emits tracked state graph metadata for imported nested paths" {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const source =
        \\<template>
        \\  <p>{{ workspace.sidebar.collapsed }}</p>
        \\  <p>{{ workspace.currentProject.name }}</p>
        \\</template>
        \\
        \\<script lang="ts">
        \\  import { workspace } from "./workspace-state.ts";
        \\</script>
    ;

    var model = try compiler_compile.compile(source, "test/examples/direct-browser-tracked-imported-paths.weiv", allocator);
    defer model.deinit(allocator);

    const js = try emitComponentJs(&model, allocator);
    defer allocator.free(js);

    try std.testing.expect(std.mem.indexOf(u8, js, "import { workspace as __weiv_import_workspace } from \"./workspace-state.js\";") != null);
    try std.testing.expect(std.mem.indexOf(u8, js, "const workspace = __weiv_getTrackedRoot(\"workspace\", __weiv_import_workspace);") != null);
    try std.testing.expect(std.mem.indexOf(u8, js, "__weiv_scope.workspace = workspace;") != null);
    try std.testing.expect(std.mem.indexOf(u8, js, "export const trackedStateGraph = { roots: [{ rootId: 1, bindingName: \"workspace\", kind: \"imported-tracked\" }], paths: [{ pathId: 1, rootId: 1, path: \"workspace\", parentPathId: null }, { pathId: 2, rootId: 1, path: \"workspace.sidebar\", parentPathId: 1 }, { pathId: 3, rootId: 1, path: \"workspace.sidebar.collapsed\", parentPathId: 2 }, { pathId: 4, rootId: 1, path: \"workspace.currentProject\", parentPathId: 1 }, { pathId: 5, rootId: 1, path: \"workspace.currentProject.name\", parentPathId: 4 }], regions: [{ regionId: 1, trackedPathIds: [3] }, { regionId: 2, trackedPathIds: [5] }] };") != null);
    try std.testing.expect(std.mem.indexOf(u8, js, "const dirtyPaths = collectTrackedDirtyPaths();") != null);
    try std.testing.expect(std.mem.indexOf(u8, js, "__weiv_markTrackedPathsForWrite(rootId, nextPath);") != null);
    try std.testing.expect(std.mem.indexOf(u8, js, "__weiv_scheduleTrackedFlush();") != null);
    try std.testing.expect(std.mem.indexOf(u8, js, "if (dirtyPathSet.size > 0 && trackedStateGraph && Array.isArray(trackedStateGraph.regions)) {") != null);
    try std.testing.expect(std.mem.indexOf(u8, js, "dirtyRegionSet.add(region.regionId);") != null);
    try std.testing.expect(std.mem.indexOf(u8, js, "if (dirtySet.has(\"workspace\") && !preciseBindingSet.has(\"workspace\") || dirtyRegionSet.has(1)) {") != null);
    try std.testing.expect(std.mem.indexOf(u8, js, "if (dirtySet.has(\"workspace\") && !preciseBindingSet.has(\"workspace\") || dirtyRegionSet.has(2)) {") != null);
}

test "direct browser module emits tracked state graph metadata for prop nested paths" {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const source =
        \\<template>
        \\  <p>{{ props.workspace.sidebar.collapsed }}</p>
        \\  <p>{{ props.workspace.currentProject.name }}</p>
        \\</template>
        \\
        \\<script lang="ts">
        \\  export interface Props {
        \\    workspace: {
        \\      sidebar: { collapsed: boolean };
        \\      currentProject: { name: string };
        \\    };
        \\  }
        \\  export let props: Props;
        \\</script>
    ;

    var model = try compiler_compile.compile(source, "test/examples/direct-browser-tracked-prop-paths.weiv", allocator);
    defer model.deinit(allocator);

    const js = try emitComponentJs(&model, allocator);
    defer allocator.free(js);

    try std.testing.expect(std.mem.indexOf(u8, js, "props = __weiv_getTrackedRoot(\"props\", props);") != null);
    try std.testing.expect(std.mem.indexOf(u8, js, "props = __weiv_getTrackedRoot(\"props\", nextProps);") != null);
    try std.testing.expect(std.mem.indexOf(u8, js, "export const trackedStateGraph = { roots: [{ rootId: 1, bindingName: \"props\", kind: \"prop-tracked\" }], paths: [{ pathId: 1, rootId: 1, path: \"props\", parentPathId: null }, { pathId: 2, rootId: 1, path: \"props.workspace\", parentPathId: 1 }, { pathId: 3, rootId: 1, path: \"props.workspace.sidebar\", parentPathId: 2 }, { pathId: 4, rootId: 1, path: \"props.workspace.sidebar.collapsed\", parentPathId: 3 }, { pathId: 5, rootId: 1, path: \"props.workspace.currentProject\", parentPathId: 2 }, { pathId: 6, rootId: 1, path: \"props.workspace.currentProject.name\", parentPathId: 5 }], regions: [{ regionId: 1, trackedPathIds: [4] }, { regionId: 2, trackedPathIds: [6] }] };") != null);
    try std.testing.expect(std.mem.indexOf(u8, js, "if (dirtySet.has(\"props\") || dirtyRegionSet.has(1)) {") != null);
    try std.testing.expect(std.mem.indexOf(u8, js, "if (dirtySet.has(\"props\") || dirtyRegionSet.has(2)) {") != null);
}

test "direct browser module emits tracked state graph metadata for local let nested paths" {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const source =
        \\<template>
        \\  <p>{{ state.profile.name }}</p>
        \\  <p>{{ state.flags.ready }}</p>
        \\</template>
        \\
        \\<script lang="ts">
        \\  let state = { profile: { name: "Ada" }, flags: { ready: true } };
        \\</script>
    ;

    var model = try compiler_compile.compile(source, "test/examples/direct-browser-tracked-local-paths.weiv", allocator);
    defer model.deinit(allocator);

    const js = try emitComponentJs(&model, allocator);
    defer allocator.free(js);

    try std.testing.expect(std.mem.indexOf(u8, js, "state = __weiv_getTrackedRoot(\"state\", state);") != null);
    try std.testing.expect(std.mem.indexOf(u8, js, "export const trackedStateGraph = { roots: [{ rootId: 1, bindingName: \"state\", kind: \"local-tracked\" }], paths: [{ pathId: 1, rootId: 1, path: \"state\", parentPathId: null }, { pathId: 2, rootId: 1, path: \"state.profile\", parentPathId: 1 }, { pathId: 3, rootId: 1, path: \"state.profile.name\", parentPathId: 2 }, { pathId: 4, rootId: 1, path: \"state.flags\", parentPathId: 1 }, { pathId: 5, rootId: 1, path: \"state.flags.ready\", parentPathId: 4 }], regions: [{ regionId: 1, trackedPathIds: [3] }, { regionId: 2, trackedPathIds: [5] }] };") != null);
    try std.testing.expect(std.mem.indexOf(u8, js, "if (dirtySet.has(\"state\") || dirtyRegionSet.has(1)) {") != null);
    try std.testing.expect(std.mem.indexOf(u8, js, "if (dirtySet.has(\"state\") || dirtyRegionSet.has(2)) {") != null);
}

test "component analysis promotes immutable local object root with nested path usage" {
    const allocator = std.testing.allocator;
    const source =
        \\<template>
        \\  <p>{{ state.profile.name }}</p>
        \\</template>
        \\
        \\<script lang="ts">
        \\  const state = { profile: { name: "Ada" } };
        \\  state.profile.name = "Grace";
        \\</script>
    ;

    var model = try compiler_compile.compile(source, "test/examples/analysis-tracked-immutable-local-root.weiv", allocator);
    defer model.deinit(allocator);

    const report = try cli.formatComponentAnalysisReport(model, allocator);
    defer allocator.free(report);

    try std.testing.expect(std.mem.indexOf(u8, report, "  tracked roots: 1\n") != null);
    try std.testing.expect(std.mem.indexOf(u8, report, "  root kinds: imported=0 props=0 local=1\n") != null);
    try std.testing.expect(std.mem.indexOf(u8, report, "    - root id=1 binding=state kind=local-tracked\n") != null);
}

test "conditional toggle direct browser module emits conditional boundary helpers" {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const source = try readFixture(allocator, "test/examples/basic/conditional-toggle.weiv");
    defer allocator.free(source);

    var model = try compiler_compile.compile(source, "test/examples/basic/conditional-toggle.weiv", allocator);
    defer model.deinit(allocator);

    const js = try emitComponentJs(&model, allocator);
    defer allocator.free(js);

    try std.testing.expect(std.mem.indexOf(u8, js, "createConditionalFragment_") != null);
    try std.testing.expect(std.mem.indexOf(u8, js, "updateConditional_") != null);
    try std.testing.expect(std.mem.indexOf(u8, js, "function updateRegion_conditional_") != null);
    try std.testing.expect(std.mem.indexOf(u8, js, "updateRegion_conditional_") != null);
    try std.testing.expect(std.mem.indexOf(u8, js, "document.createComment(\"if:start\")") != null);
    try std.testing.expect(std.mem.indexOf(u8, js, "replaceBetween(") != null);
    try std.testing.expect(std.mem.indexOf(u8, js, "function updateDirtyRegions(instance, dirtyState, scope = instance.refresh())") != null);
    try std.testing.expect(std.mem.indexOf(u8, js, "if (dirtySet.has(\"open\") || dirtyRegionSet.has(1)) {") != null);
}

test "todo list direct browser module emits loop boundary helpers" {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const source = try readFixture(allocator, "test/examples/basic/todo-list.weiv");
    defer allocator.free(source);

    var model = try compiler_compile.compile(source, "test/examples/basic/todo-list.weiv", allocator);
    defer model.deinit(allocator);

    const js = try emitComponentJs(&model, allocator);
    defer allocator.free(js);

    try std.testing.expect(std.mem.indexOf(u8, js, "createForEntry_") != null);
    try std.testing.expect(std.mem.indexOf(u8, js, "updateForLoop_") != null);
    try std.testing.expect(std.mem.indexOf(u8, js, "function updateRegion_loop_") != null);
    try std.testing.expect(std.mem.indexOf(u8, js, "updateRegion_loop_") != null);
    try std.testing.expect(std.mem.indexOf(u8, js, "document.createComment(\"for:start\")") != null);
    try std.testing.expect(std.mem.indexOf(u8, js, "let loopScope = { ...scope, [\"item\"]: currentItem };") != null);
    try std.testing.expect(std.mem.indexOf(u8, js, "loopScope = { ...nextScope, [\"item\"]: currentItem };") != null);
    try std.testing.expect(std.mem.indexOf(u8, js, "function updateDirtyRegions(instance, dirtyState, scope = instance.refresh())") != null);
    try std.testing.expect(std.mem.indexOf(u8, js, "if (dirtySet.has(\"visibleItems\") || dirtySet.has(\"items\") || dirtySet.has(\"showCompleted\") || dirtyRegionSet.has(3)) {") != null);
    try std.testing.expect(std.mem.indexOf(u8, js, "dirtySet.has(\"item\")") == null);
}

test "browser render_tree formatter exposes inspectable direct DOM render_tree duplicate coverage" {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const source = try readFixture(allocator, "test/examples/slots/CardUsage.weiv");
    defer allocator.free(source);

    var model = try compiler_compile.compile(source, "test/examples/slots/CardUsage.weiv", allocator);
    defer model.deinit(allocator);

    var render_tree = try browser_render_tree.lower(&model.lir_document, allocator);
    defer render_tree.deinit(allocator);

    const formatted = try browser_render_tree.debug.formatDocument(&render_tree, allocator);
    defer allocator.free(formatted);

    try std.testing.expect(std.mem.indexOf(u8, formatted, "render-tree next_ref_id=") != null);
    try std.testing.expect(std.mem.indexOf(u8, formatted, "component refs=[") != null);
    try std.testing.expect(std.mem.indexOf(u8, formatted, "slot-provision name=header") != null);
    try std.testing.expect(std.mem.indexOf(u8, formatted, "slot-provision name=default") != null);
}

test "invalidation graph formatter exposes regions dependencies and owned boundaries" {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const source = try readFixture(allocator, "test/examples/basic/basic-counter.weiv");
    defer allocator.free(source);

    var model = try compiler_compile.compile(source, "test/examples/basic/basic-counter.weiv", allocator);
    defer model.deinit(allocator);

    var render_tree = try browser_render_tree.lower(&model.lir_document, allocator);
    defer render_tree.deinit(allocator);

    const formatted = try invalidation_graph.formatDocument(&model, &render_tree, allocator);
    defer allocator.free(formatted);

    try std.testing.expect(std.mem.indexOf(u8, formatted, "invalidation-graph source=test/examples/basic/basic-counter.weiv") != null);
    try std.testing.expect(std.mem.indexOf(u8, formatted, "text ref=") != null);
    try std.testing.expect(std.mem.indexOf(u8, formatted, "attribute ref=") != null);
    try std.testing.expect(std.mem.indexOf(u8, formatted, "deps=[count]") != null);
    try std.testing.expect(std.mem.indexOf(u8, formatted, "expr=doubled() eval=direct deps=[doubled,count]") != null);
    try std.testing.expect(std.mem.indexOf(u8, formatted, "mutations") != null);
    try std.testing.expect(std.mem.indexOf(u8, formatted, "count assignment offset=") != null);
    try std.testing.expect(std.mem.indexOf(u8, formatted, "template-event name=click expr=increment owned=true") != null);
}

test "invalidation graph formatter expands nested local helper dependencies" {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const source =
        \\<template>
        \\  <p>{{ message() }}</p>
        \\</template>
        \\
        \\<script lang="ts">
        \\  export interface Props {}
        \\  export let props: Props;
        \\
        \\  let count = 1;
        \\
        \\  function doubled() {
        \\    return count * 2;
        \\  }
        \\
        \\  function message() {
        \\    return doubled();
        \\  }
        \\</script>
    ;

    var model = try compiler_compile.compile(source, "test/examples/invalidation-graph-local-helper-deps.weiv", allocator);
    defer model.deinit(allocator);

    var render_tree = try browser_render_tree.lower(&model.lir_document, allocator);
    defer render_tree.deinit(allocator);

    const formatted = try invalidation_graph.formatDocument(&model, &render_tree, allocator);
    defer allocator.free(formatted);

    try std.testing.expect(std.mem.indexOf(u8, formatted, "expr=message() eval=direct deps=[message,doubled,count]") != null);
    try std.testing.expect(std.mem.indexOf(u8, formatted, "hidden-state expression=message()") == null);
}

test "invalidation graph formatter diagnoses hidden-state template calls" {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const source =
        \\<template>
        \\  <p>{{ getThemeLabel() }}</p>
        \\</template>
        \\
        \\<script lang="ts">
        \\  import { getThemeLabel } from "./theme.js";
        \\</script>
    ;

    var model = try compiler_compile.compile(source, "test/examples/hidden-state-call.weiv", allocator);
    defer model.deinit(allocator);

    var render_tree = try browser_render_tree.lower(&model.lir_document, allocator);
    defer render_tree.deinit(allocator);

    const formatted = try invalidation_graph.formatDocument(&model, &render_tree, allocator);
    defer allocator.free(formatted);

    try std.testing.expect(std.mem.indexOf(u8, formatted, "diagnostics") != null);
    try std.testing.expect(std.mem.indexOf(u8, formatted, "warning hidden-state expression=getThemeLabel()") != null);
    try std.testing.expect(std.mem.indexOf(u8, formatted, "reason=no-visible-component-dependency") != null);
}

test "invalidation graph formatter inventories tracked imported nested paths" {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const source =
        \\<template>
        \\  <p>{{ workspace.sidebar.collapsed }}</p>
        \\  <p>{{ workspace.currentProject.name }}</p>
        \\</template>
        \\
        \\<script lang="ts">
        \\  import { workspace } from "./workspace-state.ts";
        \\</script>
    ;

    var model = try compiler_compile.compile(source, "test/examples/invalidation-graph-tracked-imported-paths.weiv", allocator);
    defer model.deinit(allocator);

    var render_tree = try browser_render_tree.lower(&model.lir_document, allocator);
    defer render_tree.deinit(allocator);

    const formatted = try invalidation_graph.formatDocument(&model, &render_tree, allocator);
    defer allocator.free(formatted);

    try std.testing.expect(std.mem.indexOf(u8, formatted, "tracked-roots\n  root id=1 binding=workspace kind=imported-tracked\n") != null);
    try std.testing.expect(std.mem.indexOf(u8, formatted, "tracked-paths\n  path id=1 root=1 path=workspace\n  path id=2 root=1 path=workspace.sidebar parent=1\n  path id=3 root=1 path=workspace.sidebar.collapsed parent=2\n  path id=4 root=1 path=workspace.currentProject parent=1\n  path id=5 root=1 path=workspace.currentProject.name parent=4\n") != null);
    try std.testing.expect(std.mem.indexOf(u8, formatted, "expr=workspace.sidebar.collapsed eval=direct deps=[workspace] tracked_paths=[3]") != null);
    try std.testing.expect(std.mem.indexOf(u8, formatted, "expr=workspace.currentProject.name eval=direct deps=[workspace] tracked_paths=[5]") != null);
    try std.testing.expect(std.mem.indexOf(u8, formatted, "runtime-regions\n  #1 text ref=") != null);
    try std.testing.expect(std.mem.indexOf(u8, formatted, "deps=[workspace] tracked_paths=[3]\n  #2 text ref=") != null);
    try std.testing.expect(std.mem.indexOf(u8, formatted, "deps=[workspace] tracked_paths=[5]\ntracked-roots") != null);
}

test "invalidation graph formatter inventories tracked prop nested paths" {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const source =
        \\<template>
        \\  <p>{{ props.workspace.sidebar.collapsed }}</p>
        \\  <p>{{ props.workspace.currentProject.name }}</p>
        \\</template>
        \\
        \\<script lang="ts">
        \\  export interface Props {
        \\    workspace: {
        \\      sidebar: { collapsed: boolean };
        \\      currentProject: { name: string };
        \\    };
        \\  }
        \\  export let props: Props;
        \\</script>
    ;

    var model = try compiler_compile.compile(source, "test/examples/inspect-tracked-prop-paths.weiv", allocator);
    defer model.deinit(allocator);

    var render_tree = try browser_render_tree.lower(&model.lir_document, allocator);
    defer render_tree.deinit(allocator);

    const formatted = try invalidation_graph.formatDocument(&model, &render_tree, allocator);
    defer allocator.free(formatted);

    try std.testing.expect(std.mem.indexOf(u8, formatted, "tracked-roots\n  root id=1 binding=props kind=prop-tracked\n") != null);
    try std.testing.expect(std.mem.indexOf(u8, formatted, "tracked-paths\n  path id=1 root=1 path=props\n  path id=2 root=1 path=props.workspace parent=1\n  path id=3 root=1 path=props.workspace.sidebar parent=2\n  path id=4 root=1 path=props.workspace.sidebar.collapsed parent=3\n  path id=5 root=1 path=props.workspace.currentProject parent=2\n  path id=6 root=1 path=props.workspace.currentProject.name parent=5\n") != null);
    try std.testing.expect(std.mem.indexOf(u8, formatted, "expr=props.workspace.sidebar.collapsed eval=direct deps=[props] tracked_paths=[4]") != null);
    try std.testing.expect(std.mem.indexOf(u8, formatted, "expr=props.workspace.currentProject.name eval=direct deps=[props] tracked_paths=[6]") != null);
}

test "invalidation graph formatter inventories tracked local let nested paths" {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const source =
        \\<template>
        \\  <p>{{ state.profile.name }}</p>
        \\  <p>{{ state.flags.ready }}</p>
        \\</template>
        \\
        \\<script lang="ts">
        \\  let state = { profile: { name: "Ada" }, flags: { ready: true } };
        \\</script>
    ;

    var model = try compiler_compile.compile(source, "test/examples/inspect-tracked-local-paths.weiv", allocator);
    defer model.deinit(allocator);

    var render_tree = try browser_render_tree.lower(&model.lir_document, allocator);
    defer render_tree.deinit(allocator);

    const formatted = try invalidation_graph.formatDocument(&model, &render_tree, allocator);
    defer allocator.free(formatted);

    try std.testing.expect(std.mem.indexOf(u8, formatted, "tracked-roots\n  root id=1 binding=state kind=local-tracked\n") != null);
    try std.testing.expect(std.mem.indexOf(u8, formatted, "tracked-paths\n  path id=1 root=1 path=state\n  path id=2 root=1 path=state.profile parent=1\n  path id=3 root=1 path=state.profile.name parent=2\n  path id=4 root=1 path=state.flags parent=1\n  path id=5 root=1 path=state.flags.ready parent=4\n") != null);
    try std.testing.expect(std.mem.indexOf(u8, formatted, "expr=state.profile.name eval=direct deps=[state] tracked_paths=[3]") != null);
    try std.testing.expect(std.mem.indexOf(u8, formatted, "expr=state.flags.ready eval=direct deps=[state] tracked_paths=[5]") != null);
}

test "local tracked roots are not selected when root assignment exists" {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const source =
        \\<template>
        \\  <p>{{ state.profile.name }}</p>
        \\</template>
        \\
        \\<script lang="ts">
        \\  let state = { profile: { name: "Ada" } };
        \\  function replaceState() {
        \\    state = { profile: { name: "Grace" } };
        \\  }
        \\</script>
    ;

    var model = try compiler_compile.compile(source, "test/examples/no-tracked-local-root-assignment.weiv", allocator);
    defer model.deinit(allocator);

    const js = try emitComponentJs(&model, allocator);
    defer allocator.free(js);

    try std.testing.expect(std.mem.indexOf(u8, js, "state = __weiv_getTrackedRoot(\"state\", state);") == null);
    try std.testing.expect(std.mem.indexOf(u8, js, "kind: \"local-tracked\"") == null);
}

test "invalidation graph formatter warns on tracked-root alias escape" {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const source =
        \\<template>
        \\  <p>{{ workspace.profile.name }}</p>
        \\</template>
        \\
        \\<script lang="ts">
        \\  import { workspace } from "./workspace-state.ts";
        \\  const alias = workspace;
        \\  alias.profile.name = "Grace";
        \\</script>
    ;

    var model = try compiler_compile.compile(source, "test/examples/tracked-root-alias-escape.weiv", allocator);
    defer model.deinit(allocator);

    var render_tree = try browser_render_tree.lower(&model.lir_document, allocator);
    defer render_tree.deinit(allocator);

    const formatted = try invalidation_graph.formatDocument(&model, &render_tree, allocator);
    defer allocator.free(formatted);

    try std.testing.expect(std.mem.indexOf(u8, formatted, "warning escape-warning binding=workspace related=alias") != null);
    try std.testing.expect(std.mem.indexOf(u8, formatted, "reason=tracked-root-alias-escape") != null);
    try std.testing.expect(std.mem.indexOf(u8, formatted, "warning alias-mutation binding=workspace alias=alias") != null);
}

test "invalidation graph formatter warns on tracked-root unowned callback mutation" {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const source =
        \\<template>
        \\  <p>{{ workspace.sidebar.collapsed }}</p>
        \\</template>
        \\
        \\<script lang="ts">
        \\  import { workspace } from "./workspace-state.ts";
        \\  externalStore.subscribe(() => {
        \\    workspace.sidebar.collapsed = !workspace.sidebar.collapsed;
        \\  });
        \\</script>
    ;

    var model = try compiler_compile.compile(source, "test/examples/tracked-root-unowned-callback.weiv", allocator);
    defer model.deinit(allocator);

    var render_tree = try browser_render_tree.lower(&model.lir_document, allocator);
    defer render_tree.deinit(allocator);

    const formatted = try invalidation_graph.formatDocument(&model, &render_tree, allocator);
    defer allocator.free(formatted);

    try std.testing.expect(std.mem.indexOf(u8, formatted, "warning escape-warning binding=workspace related= offset=") != null);
    try std.testing.expect(std.mem.indexOf(u8, formatted, "reason=tracked-root-unowned-callback") != null);
    try std.testing.expect(std.mem.indexOf(u8, formatted, "warning unowned-callback-mutation binding=workspace") != null);
}

test "invalidation graph formatter diagnoses local helper external reads" {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const source =
        \\<template>
        \\  <p>{{ themeLabel() }}</p>
        \\</template>
        \\
        \\<script lang="ts">
        \\  export interface Props {}
        \\  export let props: Props;
        \\
        \\  function themeLabel() {
        \\    return globalThis.__theme?.label ?? "Default";
        \\  }
        \\</script>
    ;

    var model = try compiler_compile.compile(source, "test/examples/local-helper-hidden-state.weiv", allocator);
    defer model.deinit(allocator);

    var render_tree = try browser_render_tree.lower(&model.lir_document, allocator);
    defer render_tree.deinit(allocator);

    const formatted = try invalidation_graph.formatDocument(&model, &render_tree, allocator);
    defer allocator.free(formatted);

    try std.testing.expect(std.mem.indexOf(u8, formatted, "expr=themeLabel()") != null);
    try std.testing.expect(std.mem.indexOf(u8, formatted, "warning hidden-state expression=themeLabel() reason=helper-contains-external-reads") != null);
}

test "invalidation graph formatter diagnoses local helper side effects" {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const source =
        \\<template>
        \\  <p>{{ nextCount() }}</p>
        \\</template>
        \\
        \\<script lang="ts">
        \\  export interface Props {}
        \\  export let props: Props;
        \\
        \\  let count = 0;
        \\
        \\  function nextCount() {
        \\    count += 1;
        \\    return count;
        \\  }
        \\</script>
    ;

    var model = try compiler_compile.compile(source, "test/examples/local-helper-side-effects.weiv", allocator);
    defer model.deinit(allocator);

    var render_tree = try browser_render_tree.lower(&model.lir_document, allocator);
    defer render_tree.deinit(allocator);

    const formatted = try invalidation_graph.formatDocument(&model, &render_tree, allocator);
    defer allocator.free(formatted);

    try std.testing.expect(std.mem.indexOf(u8, formatted, "expr=nextCount()") != null);
    try std.testing.expect(std.mem.indexOf(u8, formatted, "warning hidden-state expression=nextCount() reason=helper-contains-side-effects") != null);
}

test "invalidation graph formatter marks simple callback-argument expressions as direct" {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const source =
        \\<template>
        \\  <p>{{ items.filter((item) => item.done).length }}</p>
        \\</template>
        \\
        \\<script lang="ts">
        \\  export interface Props {}
        \\  export let props: Props;
        \\
        \\  let items = [{ done: true }, { done: false }];
        \\</script>
    ;

    var model = try compiler_compile.compile(source, "test/examples/invalidation-graph-evaluate-fallback.weiv", allocator);
    defer model.deinit(allocator);

    var render_tree = try browser_render_tree.lower(&model.lir_document, allocator);
    defer render_tree.deinit(allocator);

    const formatted = try invalidation_graph.formatDocument(&model, &render_tree, allocator);
    defer allocator.free(formatted);

    try std.testing.expect(std.mem.indexOf(u8, formatted, "expr=items.filter((item) => item.done).length eval=direct deps=[items]") != null);
    try std.testing.expect(std.mem.indexOf(u8, formatted, "runtime-evaluate-fallback expression=items.filter((item) => item.done).length") == null);
    try std.testing.expect(std.mem.indexOf(u8, formatted, "reason=callback-argument") == null);
}

test "invalidation graph formatter marks block-bodied callback-argument expressions as direct" {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const source =
        \\<template>
        \\  <p>{{ items.filter((item) => { return item.done; }).length }}</p>
        \\</template>
        \\
        \\<script lang="ts">
        \\  export interface Props {}
        \\  export let props: Props;
        \\
        \\  let items = [{ done: true }, { done: false }];
        \\</script>
    ;

    var model = try compiler_compile.compile(source, "test/examples/invalidation-graph-block-callback-evaluate-fallback.weiv", allocator);
    defer model.deinit(allocator);

    var render_tree = try browser_render_tree.lower(&model.lir_document, allocator);
    defer render_tree.deinit(allocator);

    const formatted = try invalidation_graph.formatDocument(&model, &render_tree, allocator);
    defer allocator.free(formatted);

    try std.testing.expect(std.mem.indexOf(u8, formatted, "expr=items.filter((item) => { return item.done; }).length eval=direct deps=[items]") != null);
    try std.testing.expect(std.mem.indexOf(u8, formatted, "runtime-evaluate-fallback expression=items.filter((item) => { return item.done; }).length") == null);
    try std.testing.expect(std.mem.indexOf(u8, formatted, "reason=callback-argument") == null);
}

test "invalidation graph formatter marks bracket-access expressions as direct" {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const source =
        \\<template>
        \\  <p>{{ items[selectedIndex].title }}</p>
        \\</template>
        \\
        \\<script lang="ts">
        \\  export interface Props {}
        \\  export let props: Props;
        \\
        \\  let selectedIndex = 0;
        \\  let items = [{ title: "One" }, { title: "Two" }];
        \\</script>
    ;

    var model = try compiler_compile.compile(source, "test/examples/invalidation-graph-bracket-access.weiv", allocator);
    defer model.deinit(allocator);

    var render_tree = try browser_render_tree.lower(&model.lir_document, allocator);
    defer render_tree.deinit(allocator);

    const formatted = try invalidation_graph.formatDocument(&model, &render_tree, allocator);
    defer allocator.free(formatted);

    try std.testing.expect(std.mem.indexOf(u8, formatted, "expr=items[selectedIndex].title eval=direct deps=[items,selectedIndex]") != null);
    try std.testing.expect(std.mem.indexOf(u8, formatted, "runtime-evaluate-fallback expression=items[selectedIndex].title") == null);
}

test "invalidation graph formatter lists object and container mutation sites" {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const source =
        \\<template>
        \\  <button @click="mutate">{{ todos.length }}</button>
        \\</template>
        \\
        \\<script lang="ts">
        \\  export interface Props {}
        \\  export let props: Props;
        \\
        \\  let todos = [{ done: false }];
        \\
        \\  function mutate() {
        \\    todos.push({ done: false });
        \\    todos[0].done = true;
        \\  }
        \\</script>
    ;

    var model = try compiler_compile.compile(source, "test/examples/invalidation-graph-mutations.weiv", allocator);
    defer model.deinit(allocator);

    var render_tree = try browser_render_tree.lower(&model.lir_document, allocator);
    defer render_tree.deinit(allocator);

    const formatted = try invalidation_graph.formatDocument(&model, &render_tree, allocator);
    defer allocator.free(formatted);

    try std.testing.expect(std.mem.indexOf(u8, formatted, "todos method offset=") != null);
    try std.testing.expect(std.mem.indexOf(u8, formatted, "todos member-assignment offset=") != null);
    try std.testing.expect(std.mem.indexOf(u8, formatted, "template-event name=click expr=mutate owned=true") != null);
}

test "invalidation graph formatter classifies fallback expressions as info" {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const source =
        \\<template>
        \\  <p>{{ items.map(function (item) { return item.done; }).length }}</p>
        \\</template>
        \\
        \\<script lang="ts">
        \\  export interface Props {}
        \\  export let props: Props;
        \\
        \\  let items = [{ done: true }, { done: false }];
        \\</script>
    ;

    var model = try compiler_compile.compile(source, "test/examples/invalidation-graph-fallback-info.weiv", allocator);
    defer model.deinit(allocator);

    var render_tree = try browser_render_tree.lower(&model.lir_document, allocator);
    defer render_tree.deinit(allocator);

    const formatted = try invalidation_graph.formatDocument(&model, &render_tree, allocator);
    defer allocator.free(formatted);

    try std.testing.expect(std.mem.indexOf(u8, formatted, "expr=items.map(function (item) { return item.done; }).length eval=fallback reason=dynamic-call-arguments deps=[items]") != null);
    try std.testing.expect(std.mem.indexOf(u8, formatted, "info runtime-evaluate-fallback expression=items.map(function (item) { return item.done; }).length reason=dynamic-call-arguments") != null);
}

test "invalidation graph formatter diagnoses expression-position mutations" {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const source =
        \\<template>
        \\  <button @click="mutate">{{ count }}</button>
        \\</template>
        \\
        \\<script lang="ts">
        \\  export interface Props {}
        \\  export let props: Props;
        \\
        \\  let count = 0;
        \\
        \\  function mutate() {
        \\    const next = count++;
        \\    return next;
        \\  }
        \\</script>
    ;

    var model = try compiler_compile.compile(source, "test/examples/invalidation-graph-expression-mutation.weiv", allocator);
    defer model.deinit(allocator);

    var render_tree = try browser_render_tree.lower(&model.lir_document, allocator);
    defer render_tree.deinit(allocator);

    const formatted = try invalidation_graph.formatDocument(&model, &render_tree, allocator);
    defer allocator.free(formatted);

    try std.testing.expect(std.mem.indexOf(u8, formatted, "diagnostics") != null);
    try std.testing.expect(std.mem.indexOf(u8, formatted, "warning expression-mutation binding=count") != null);
    try std.testing.expect(std.mem.indexOf(u8, formatted, "reason=mutation-not-in-statement-position") != null);
}

test "invalidation graph formatter classifies child event boundaries as owned" {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const source = try readFixture(allocator, "test/examples/todomvc/TodoList.weiv");
    defer allocator.free(source);

    var model = try compiler_compile.compile(source, "test/examples/todomvc/TodoList.weiv", allocator);
    defer model.deinit(allocator);

    var render_tree = try browser_render_tree.lower(&model.lir_document, allocator);
    defer render_tree.deinit(allocator);

    const formatted = try invalidation_graph.formatDocument(&model, &render_tree, allocator);
    defer allocator.free(formatted);

    try std.testing.expect(std.mem.indexOf(u8, formatted, "child-event name=toggle expr=emitToggle owned=true") != null);
    try std.testing.expect(std.mem.indexOf(u8, formatted, "child-event name=save-edit expr=emitSave owned=true") != null);
}

test "invalidation graph formatter classifies async template event handlers as owned" {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const source =
        \\<template>
        \\  <button @click="load">{{ status }}</button>
        \\</template>
        \\
        \\<script lang="ts">
        \\  export interface Props {}
        \\  export let props: Props;
        \\
        \\  let status = "idle";
        \\
        \\  async function load() {
        \\    status = "loading";
        \\    await Promise.resolve();
        \\    status = "done";
        \\  }
        \\</script>
    ;

    var model = try compiler_compile.compile(source, "test/examples/invalidation-graph-async-event.weiv", allocator);
    defer model.deinit(allocator);

    var render_tree = try browser_render_tree.lower(&model.lir_document, allocator);
    defer render_tree.deinit(allocator);

    const formatted = try invalidation_graph.formatDocument(&model, &render_tree, allocator);
    defer allocator.free(formatted);

    try std.testing.expect(std.mem.indexOf(u8, formatted, "template-event name=click expr=load owned=true async=true") != null);
    try std.testing.expect(std.mem.indexOf(u8, formatted, "status assignment offset=") != null);
}

test "invalidation graph formatter diagnoses observable mutation inside unowned callback" {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const source =
        \\<template>
        \\  <p>{{ count }}</p>
        \\</template>
        \\
        \\<script lang="ts">
        \\  export interface Props {}
        \\  export let props: Props;
        \\
        \\  let count = 0;
        \\
        \\  externalStore.subscribe(() => {
        \\    count += 1;
        \\  });
        \\</script>
    ;

    var model = try compiler_compile.compile(source, "test/examples/invalidation-graph-unowned-callback.weiv", allocator);
    defer model.deinit(allocator);

    var render_tree = try browser_render_tree.lower(&model.lir_document, allocator);
    defer render_tree.deinit(allocator);

    const formatted = try invalidation_graph.formatDocument(&model, &render_tree, allocator);
    defer allocator.free(formatted);

    try std.testing.expect(std.mem.indexOf(u8, formatted, "callback-registrations") != null);
    try std.testing.expect(std.mem.indexOf(u8, formatted, "callback callee=externalStore.subscribe kind=inline_arrow owned_candidate=false reason=unknown_registration") != null);
    try std.testing.expect(std.mem.indexOf(u8, formatted, "diagnostics") != null);
    try std.testing.expect(std.mem.indexOf(u8, formatted, "warning unowned-callback-mutation binding=count") != null);
    try std.testing.expect(std.mem.indexOf(u8, formatted, "reason=callback-boundary-not-owned") != null);
    try std.testing.expect(std.mem.indexOf(u8, formatted, "count assignment offset=") == null);
}

test "invalidation graph formatter diagnoses observable alias mutation" {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const source =
        \\<template>
        \\  <p>{{ user.name }}</p>
        \\</template>
        \\
        \\<script lang="ts">
        \\  export interface Props {}
        \\  export let props: Props;
        \\
        \\  let user = { name: "Grace" };
        \\  const alias = user;
        \\
        \\  function rename() {
        \\    alias.name = "Ada";
        \\  }
        \\</script>
    ;

    var model = try compiler_compile.compile(source, "test/examples/invalidation-graph-alias-mutation.weiv", allocator);
    defer model.deinit(allocator);

    var render_tree = try browser_render_tree.lower(&model.lir_document, allocator);
    defer render_tree.deinit(allocator);

    const formatted = try invalidation_graph.formatDocument(&model, &render_tree, allocator);
    defer allocator.free(formatted);

    try std.testing.expect(std.mem.indexOf(u8, formatted, "diagnostics") != null);
    try std.testing.expect(std.mem.indexOf(u8, formatted, "warning alias-mutation binding=user alias=alias") != null);
    try std.testing.expect(std.mem.indexOf(u8, formatted, "reason=alias-tracking-not-implemented") != null);
}

test "direct browser setup wraps timer callbacks in owned boundaries" {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const source = try readFixture(allocator, "test/examples/basic/timer-callback.weiv");
    defer allocator.free(source);

    var model = try compiler_compile.compile(source, "test/examples/basic/timer-callback.weiv", allocator);
    defer model.deinit(allocator);

    const js = try emitComponentJs(&model, allocator);
    defer allocator.free(js);

    try std.testing.expect(std.mem.indexOf(u8, js, "const setTimeout = (callback, ...args) => globalThis.setTimeout(__weiv_wrapCallback(callback), ...args);") != null);
    try std.testing.expect(std.mem.indexOf(u8, js, "setBoundaryRunner: __weiv_setBoundaryRunner") != null);
    try std.testing.expect(std.mem.indexOf(u8, js, "instance.setBoundaryRunner((callback) => runOwnedBoundary(instance, callback));") != null);
}

test "slot outlet and default projection survive through normalized template and LIR" {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const source =
        \\<template>
        \\  <Panel>
        \\    <p>{{ props.message }}</p>
        \\  </Panel>
        \\</template>
        \\
        \\<script lang="ts">
        \\  import Panel from "./Panel.weiv";
        \\
        \\  export interface Props {
        \\    message: string;
        \\  }
        \\
        \\  export let props: Props;
        \\</script>
    ;

    var model = try compiler_compile.compile(source, "test/examples/slots/PanelUsage.weiv", allocator);
    defer model.deinit(allocator);

    try std.testing.expectEqual(@as(usize, 1), model.normalized_template.nodes.len);
    switch (model.normalized_template.nodes[0]) {
        .element => |element| {
            try std.testing.expect(std.mem.eql(u8, element.tag_name, "Panel"));
            try std.testing.expectEqual(@as(usize, 1), element.children.len);
        },
        else => return error.UnexpectedNormalizedShape,
    }

    try std.testing.expectEqual(@as(usize, 1), model.lir_document.nodes.len);
    switch (model.lir_document.nodes[0]) {
        .component => |component_node| {
            try std.testing.expect(std.mem.eql(u8, component_node.tag_name, "Panel"));
            try std.testing.expectEqual(@as(usize, 1), component_node.slot_provisions.len);
            try std.testing.expect(component_node.slot_provisions[0].name == null);
            try std.testing.expectEqual(@as(usize, 1), component_node.slot_provisions[0].children.len);
            switch (component_node.slot_provisions[0].children[0]) {
                .element => |child| try std.testing.expect(std.mem.eql(u8, child.tag_name, "p")),
                else => return error.UnexpectedIrShape,
            }
        },
        else => return error.UnexpectedIrShape,
    }
}

test "slot outlet parses and lowers fallback content" {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const source =
        \\<template>
        \\  <section>
        \\    <slot>
        \\      <p>Fallback</p>
        \\    </slot>
        \\  </section>
        \\</template>
        \\
        \\<script lang="ts">
        \\  export interface Props {}
        \\  export let props: Props;
        \\</script>
    ;

    var model = try compiler_compile.compile(source, "test/examples/slots/Panel.weiv", allocator);
    defer model.deinit(allocator);

    switch (model.normalized_template.nodes[0]) {
        .element => |root| {
            try std.testing.expectEqual(@as(usize, 1), root.children.len);
            switch (root.children[0]) {
                .slot_outlet => |slot_outlet| {
                    try std.testing.expect(slot_outlet.name == null);
                    try std.testing.expectEqual(@as(usize, 1), slot_outlet.fallback_children.len);
                },
                else => return error.UnexpectedNormalizedShape,
            }
        },
        else => return error.UnexpectedNormalizedShape,
    }

    switch (model.lir_document.nodes[0]) {
        .element => |root| {
            try std.testing.expectEqual(@as(usize, 1), root.children.len);
            switch (root.children[0]) {
                .slot_outlet => |slot_outlet| {
                    try std.testing.expect(slot_outlet.name == null);
                    try std.testing.expectEqual(@as(usize, 1), slot_outlet.fallback_children.len);
                },
                else => return error.UnexpectedIrShape,
            }
        },
        else => return error.UnexpectedIrShape,
    }
}

test "direct browser modules expose default slot projection contract" {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const panel_source = try readFixture(allocator, "test/examples/slots/Panel.weiv");
    defer allocator.free(panel_source);
    var panel_model = try compiler_compile.compile(panel_source, "test/examples/slots/Panel.weiv", allocator);
    defer panel_model.deinit(allocator);

    const panel_usage_source = try readFixture(allocator, "test/examples/slots/PanelUsage.weiv");
    defer allocator.free(panel_usage_source);
    var usage_model = try compiler_compile.compile(panel_usage_source, "test/examples/slots/PanelUsage.weiv", allocator);
    defer usage_model.deinit(allocator);

    const panel_js = try emitComponentJs(&panel_model, allocator);
    defer allocator.free(panel_js);
    const usage_js = try emitComponentJs(&usage_model, allocator);
    defer allocator.free(usage_js);

    try std.testing.expect(std.mem.indexOf(u8, panel_js, "instance.slots?.default") != null);
    try std.testing.expect(std.mem.indexOf(u8, panel_js, "export function mountIntoBoundary(start, end, props = {}, eventHandlers = {}, slots = {})") != null);
    try std.testing.expect(std.mem.indexOf(u8, panel_js, "setSlots: instance.setSlots") != null);
    try std.testing.expect(std.mem.indexOf(u8, panel_js, "function createSlotFallbackFragment_") != null);
    try std.testing.expect(std.mem.indexOf(u8, panel_js, "function updateRegion_slot_2") != null);
    try std.testing.expect(std.mem.indexOf(u8, panel_js, "updateRegion_slot_2(instance, scope, refs);") != null);
    try std.testing.expect(std.mem.indexOf(u8, panel_js, "refs[2] = false;") != null);
    try std.testing.expect(std.mem.indexOf(u8, panel_js, "const __next_slot_2 = instance.slots?.default;") != null);
    try std.testing.expect(std.mem.indexOf(u8, panel_js, "refs[2] = __next_slot_2.mountIntoBoundary(refs[0], refs[1]);") != null);
    try std.testing.expect(std.mem.indexOf(u8, panel_js, "replaceBetween(refs[0], refs[1], createSlotFallbackFragment_2(instance, scope));") != null);
    try std.testing.expect(std.mem.indexOf(u8, usage_js, "mountProjectedSlot_") != null);
    try std.testing.expect(std.mem.indexOf(u8, usage_js, ".mountIntoBoundary(") != null);
    try std.testing.expect(std.mem.indexOf(u8, usage_js, "default: { mountIntoBoundary: (start, end) => mountProjectedSlot_") != null);
}

test "named slot grouping lowers into explicit slot provisions" {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const source = try readFixture(allocator, "test/examples/slots/CardUsage.weiv");
    defer allocator.free(source);

    var model = try compiler_compile.compile(source, "test/examples/slots/CardUsage.weiv", allocator);
    defer model.deinit(allocator);

    try std.testing.expectEqual(@as(usize, 1), model.lir_document.nodes.len);
    switch (model.lir_document.nodes[0]) {
        .component => |component_node| {
            try std.testing.expect(std.mem.eql(u8, component_node.tag_name, "Card"));
            try std.testing.expectEqual(@as(usize, 2), component_node.slot_provisions.len);
            try std.testing.expect(std.mem.eql(u8, component_node.slot_provisions[0].name.?, "header"));
            try std.testing.expectEqual(@as(usize, 2), component_node.slot_provisions[0].children.len);
            try std.testing.expect(component_node.slot_provisions[1].name == null);
            try std.testing.expectEqual(@as(usize, 1), component_node.slot_provisions[1].children.len);
        },
        else => return error.UnexpectedIrShape,
    }
}

test "named slot browser modules expose slot map contract" {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const card_source = try readFixture(allocator, "test/examples/slots/Card.weiv");
    defer allocator.free(card_source);
    var card_model = try compiler_compile.compile(card_source, "test/examples/slots/Card.weiv", allocator);
    defer card_model.deinit(allocator);

    const card_usage_source = try readFixture(allocator, "test/examples/slots/CardUsage.weiv");
    defer allocator.free(card_usage_source);
    var usage_model = try compiler_compile.compile(card_usage_source, "test/examples/slots/CardUsage.weiv", allocator);
    defer usage_model.deinit(allocator);

    const card_js = try emitComponentJs(&card_model, allocator);
    defer allocator.free(card_js);
    const usage_js = try emitComponentJs(&usage_model, allocator);
    defer allocator.free(usage_js);

    try std.testing.expect(std.mem.indexOf(u8, card_js, "instance.slots?.[\"header\"]") != null);
    try std.testing.expect(std.mem.indexOf(u8, card_js, "function createSlotFallbackFragment_2(instance, scope)") != null);
    try std.testing.expect(std.mem.indexOf(u8, card_js, "function createSlotFallbackFragment_7(instance, scope)") != null);
    try std.testing.expect(std.mem.indexOf(u8, card_js, "const __next_slot_2 = instance.slots?.[\"header\"];") != null);
    try std.testing.expect(std.mem.indexOf(u8, card_js, "refs[2] = __next_slot_2.mountIntoBoundary(refs[0], refs[1]);") != null);
    try std.testing.expect(std.mem.indexOf(u8, card_js, "replaceBetween(refs[0], refs[1], createSlotFallbackFragment_2(instance, scope));") != null);
    try std.testing.expect(std.mem.indexOf(u8, card_js, "const __next_slot_7 = instance.slots?.default;") != null);
    try std.testing.expect(std.mem.indexOf(u8, card_js, "refs[7] = __next_slot_7.mountIntoBoundary(refs[5], refs[6]);") != null);
    try std.testing.expect(std.mem.indexOf(u8, card_js, "replaceBetween(refs[5], refs[6], createSlotFallbackFragment_7(instance, scope));") != null);
    try std.testing.expect(std.mem.indexOf(u8, usage_js, "mountProjectedSlot_") != null);
    try std.testing.expect(std.mem.indexOf(u8, usage_js, "\"header\": { mountIntoBoundary: (start, end) => mountProjectedSlot_") != null);
    try std.testing.expect(std.mem.indexOf(u8, usage_js, "default: { mountIntoBoundary: (start, end) => mountProjectedSlot_") != null);
}

test "slot assignment outside component usage is rejected" {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const source =
        \\<template>
        \\  <div slot:header>Wrong place</div>
        \\</template>
        \\
        \\<script lang="ts">
        \\  export interface Props {}
        \\  export let props: Props;
        \\</script>
    ;

    try std.testing.expectError(
        error.InvalidSlotPlacement,
        compiler_compile.compile(source, "inline-invalid-slot-placement.weiv", allocator),
    );
}

test "template grouping without slot assignment is rejected" {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const source =
        \\<template>
        \\  <Card>
        \\    <template>
        \\      <p>Wrong place</p>
        \\    </template>
        \\  </Card>
        \\</template>
        \\
        \\<script lang="ts">
        \\  import Card from "./Card.weiv";
        \\  export interface Props {}
        \\  export let props: Props;
        \\</script>
    ;

    try std.testing.expectError(
        error.InvalidSlotTemplatePlacement,
        compiler_compile.compile(source, "inline-invalid-slot-template.weiv", allocator),
    );
}

test "dangling else without sibling if is rejected" {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const source =
        \\<template>
        \\  <div #else>Wrong place</div>
        \\</template>
        \\
        \\<script lang="ts">
        \\  export interface Props {}
        \\  export let props: Props;
        \\</script>
    ;

    try std.testing.expectError(
        error.UnexpectedElse,
        compiler_compile.compile(source, "inline-unexpected-else.weiv", allocator),
    );
}

test "slot outlet directives are rejected" {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const source =
        \\<template>
        \\  <slot slot:header></slot>
        \\</template>
        \\
        \\<script lang="ts">
        \\  export interface Props {}
        \\  export let props: Props;
        \\</script>
    ;

    try std.testing.expectError(
        error.InvalidSlotOutlet,
        compiler_compile.compile(source, "inline-invalid-slot-outlet.weiv", allocator),
    );
}

test "template grouping outside component usage is rejected" {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const source =
        \\<template>
        \\  <template slot:header>
        \\    <p>Wrong place</p>
        \\  </template>
        \\</template>
        \\
        \\<script lang="ts">
        \\  export interface Props {}
        \\  export let props: Props;
        \\</script>
    ;

    try std.testing.expectError(
        error.InvalidSlotTemplatePlacement,
        compiler_compile.compile(source, "inline-invalid-top-level-template.weiv", allocator),
    );
}

test "todomvc app direct browser module preserves child component imports" {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const source = try readFixture(allocator, "test/examples/todomvc/App.weiv");
    defer allocator.free(source);

    var model = try compiler_compile.compile(source, "test/examples/todomvc/App.weiv", allocator);
    defer model.deinit(allocator);

    const js = try emitComponentJs(&model, allocator);
    defer allocator.free(js);

    try std.testing.expect(std.mem.indexOf(u8, js, "import * as TodoHeader from \"./TodoHeader.mjs\";") != null);
    try std.testing.expect(std.mem.indexOf(u8, js, "import * as TodoList from \"./TodoList.mjs\";") != null);
    try std.testing.expect(std.mem.indexOf(u8, js, "import * as TodoFooter from \"./TodoFooter.mjs\";") != null);
    try std.testing.expect(std.mem.indexOf(u8, js, ".mountIntoBoundary(") != null);
    try std.testing.expect(std.mem.indexOf(u8, js, "function updateRegion_child_") != null);
    try std.testing.expect(std.mem.indexOf(u8, js, "updateRegion_child_") != null);
    try std.testing.expect(std.mem.indexOf(u8, js, ".setProps(") != null);
    try std.testing.expect(std.mem.indexOf(u8, js, ".setEventHandlers(") != null);
    try std.testing.expect(std.mem.indexOf(u8, js, "(payload) => runOwnedBoundary(instance, () => {") != null);
    try std.testing.expect(std.mem.indexOf(u8, js, "return resolved(payload);") != null);
    try std.testing.expect(std.mem.indexOf(u8, js, "const next = Boolean(scope.todos.length > 0);") != null);
    try std.testing.expect(std.mem.indexOf(u8, js, "const __props_9 = {\"editingId\": scope.editingId, \"items\": scope.visibleTodos()};") != null);
    try std.testing.expect(std.mem.indexOf(u8, js, "const __props_16 = {\"activeCount\": scope.activeCount(), \"completedCount\": scope.completedCount(), \"filter\": scope.filter};") != null);
    try std.testing.expect(std.mem.indexOf(u8, js, "const __value_6_checked = scope.isAllCompleted();") != null);
}

test "conditional direct browser modules destroy outgoing branch before replacement duplicate coverage" {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const source = try readFixture(allocator, "test/examples/basic/conditional-toggle.weiv");
    defer allocator.free(source);

    var model = try compiler_compile.compile(source, "test/examples/basic/conditional-toggle.weiv", allocator);
    defer model.deinit(allocator);

    const js = try emitComponentJs(&model, allocator);
    defer allocator.free(js);

    try std.testing.expect(std.mem.indexOf(u8, js, "function destroyConditionalBranch_") != null);
    try std.testing.expect(std.mem.indexOf(u8, js, "const previous = refs[") != null);
    try std.testing.expect(std.mem.indexOf(u8, js, "destroyConditionalBranch_") != null);
    try std.testing.expect(std.mem.indexOf(u8, js, "replaceBetween(refs[") != null);
}

test "direct browser modules emit specialized bound attribute patch code" {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const counter_source = try readFixture(allocator, "test/examples/basic/basic-counter.weiv");
    defer allocator.free(counter_source);
    var counter_model = try compiler_compile.compile(counter_source, "test/examples/basic/basic-counter.weiv", allocator);
    defer counter_model.deinit(allocator);

    const counter_js = try emitComponentJs(&counter_model, allocator);
    defer allocator.free(counter_js);

    try std.testing.expect(std.mem.indexOf(u8, counter_js, "applyBoundAttribute(") == null);
    try std.testing.expect(std.mem.indexOf(u8, counter_js, "const __next_") != null);
    try std.testing.expect(std.mem.indexOf(u8, counter_js, "_disabled = Boolean(__value_") != null);
    try std.testing.expect(std.mem.indexOf(u8, counter_js, ".disabled !== __next_") != null);
    try std.testing.expect(std.mem.indexOf(u8, counter_js, ".hasAttribute(\"disabled\")") != null);
    try std.testing.expect(std.mem.indexOf(u8, counter_js, ".disabled = __next_") != null);
    try std.testing.expect(std.mem.indexOf(u8, counter_js, ".setAttribute(\"disabled\", \"\")") != null);
    try std.testing.expect(std.mem.indexOf(u8, counter_js, "const __next_text_2 = String((scope.count) ?? \"\");") != null);
    try std.testing.expect(std.mem.indexOf(u8, counter_js, "const __value_6_disabled = scope.count >= scope.limit;") != null);

    const todo_item_source = try readFixture(allocator, "test/examples/todomvc/TodoItem.weiv");
    defer allocator.free(todo_item_source);
    var todo_item_model = try compiler_compile.compile(todo_item_source, "test/examples/todomvc/TodoItem.weiv", allocator);
    defer todo_item_model.deinit(allocator);

    const todo_item_js = try emitComponentJs(&todo_item_model, allocator);
    defer allocator.free(todo_item_js);

    try std.testing.expect(std.mem.indexOf(u8, todo_item_js, "applyBoundAttribute(") == null);
    try std.testing.expect(std.mem.indexOf(u8, todo_item_js, "getAttribute(\"class\") !== __next_attr_0_class") == null);
    try std.testing.expect(std.mem.indexOf(u8, todo_item_js, "hasAttribute(\"checked\")") != null);
    try std.testing.expect(std.mem.indexOf(u8, todo_item_js, ".checked = __next_") != null);
    try std.testing.expect(std.mem.indexOf(u8, todo_item_js, ".setAttribute(\"checked\", \"\")") != null);

    const text_input_source = try readFixture(allocator, "test/examples/todomvc/TodoTextInput.weiv");
    defer allocator.free(text_input_source);
    var text_input_model = try compiler_compile.compile(text_input_source, "test/examples/todomvc/TodoTextInput.weiv", allocator);
    defer text_input_model.deinit(allocator);

    const text_input_js = try emitComponentJs(&text_input_model, allocator);
    defer allocator.free(text_input_js);

    try std.testing.expect(std.mem.indexOf(u8, text_input_js, "const __next_0_value = __value_0_value ?? \"\";") != null);
    try std.testing.expect(std.mem.indexOf(u8, text_input_js, "const __next_string_0_value = String(__next_0_value);") != null);
    try std.testing.expect(std.mem.indexOf(u8, text_input_js, ".value !== __next_string_0_value") != null);
    try std.testing.expect(std.mem.indexOf(u8, text_input_js, "getAttribute(\"value\") !== __next_string_0_value") == null);
    try std.testing.expect(std.mem.indexOf(u8, text_input_js, ".setAttribute(\"value\", __next_string_0_value);") != null);

    const todo_footer_source = try readFixture(allocator, "test/examples/todomvc/TodoFooter.weiv");
    defer allocator.free(todo_footer_source);
    var todo_footer_model = try compiler_compile.compile(todo_footer_source, "test/examples/todomvc/TodoFooter.weiv", allocator);
    defer todo_footer_model.deinit(allocator);

    const todo_footer_js = try emitComponentJs(&todo_footer_model, allocator);
    defer allocator.free(todo_footer_js);

    try std.testing.expect(std.mem.indexOf(u8, todo_footer_js, "const __next_text_0 = String((scope.props.activeCount) ?? \"\");") != null);
    try std.testing.expect(std.mem.indexOf(u8, todo_footer_js, "const __next_text_2 = String((scope.props.activeCount === 1 ? \" item left\" : \" items left\") ?? \"\");") != null);
    try std.testing.expect(std.mem.indexOf(u8, todo_footer_js, "const next = Boolean(scope.props.completedCount > 0);") != null);
    try std.testing.expect(std.mem.indexOf(u8, todo_footer_js, "const __value_5_class = scope.filterClass('all');") != null);
    try std.testing.expect(std.mem.indexOf(u8, todo_footer_js, "const __value_7_class = scope.filterClass('active');") != null);
    try std.testing.expect(std.mem.indexOf(u8, todo_footer_js, "const __value_9_class = scope.filterClass('completed');") != null);
}

test "direct browser modules specialize child component update paths" {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const static_source =
        \\<template>
        \\  <Shell></Shell>
        \\</template>
        \\
        \\<script lang="ts">
        \\  import Shell from "./Shell.weiv";
        \\  export interface Props {}
        \\  export let props: Props;
        \\</script>
    ;

    var static_model = try compiler_compile.compile(static_source, "inline-static-child.weiv", allocator);
    defer static_model.deinit(allocator);

    const static_js = try emitComponentJs(&static_model, allocator);
    defer allocator.free(static_js);

    try std.testing.expect(std.mem.indexOf(u8, static_js, "Shell.mountIntoBoundary(") != null);
    try std.testing.expect(std.mem.indexOf(u8, static_js, "undefined, undefined, undefined") != null);
    try std.testing.expect(std.mem.indexOf(u8, static_js, "refs[2].setProps(") == null);
    try std.testing.expect(std.mem.indexOf(u8, static_js, "refs[2].setEventHandlers(") == null);
    try std.testing.expect(std.mem.indexOf(u8, static_js, "refs[2].setSlots(") == null);
    try std.testing.expect(std.mem.indexOf(u8, static_js, "refs[2].update();") == null);

    const panel_usage_source = try readFixture(allocator, "test/examples/slots/PanelUsage.weiv");
    defer allocator.free(panel_usage_source);
    var panel_usage_model = try compiler_compile.compile(panel_usage_source, "test/examples/slots/PanelUsage.weiv", allocator);
    defer panel_usage_model.deinit(allocator);

    const panel_usage_js = try emitComponentJs(&panel_usage_model, allocator);
    defer allocator.free(panel_usage_js);

    try std.testing.expect(std.mem.indexOf(u8, panel_usage_js, ".setProps(") == null);
    try std.testing.expect(std.mem.indexOf(u8, panel_usage_js, ".setEventHandlers(") == null);
    try std.testing.expect(std.mem.indexOf(u8, panel_usage_js, "refs[4].setSlots(") != null);
    try std.testing.expect(std.mem.indexOf(u8, panel_usage_js, "refs[4].update();") != null);

    const todo_item_source = try readFixture(allocator, "test/examples/todomvc/TodoItem.weiv");
    defer allocator.free(todo_item_source);
    var todo_item_model = try compiler_compile.compile(todo_item_source, "test/examples/todomvc/TodoItem.weiv", allocator);
    defer todo_item_model.deinit(allocator);

    const todo_item_js = try emitComponentJs(&todo_item_model, allocator);
    defer allocator.free(todo_item_js);

    try std.testing.expect(std.mem.indexOf(u8, todo_item_js, "const __props_5 = {\"editing\": true, \"initialValue\": scope.props.todo.title, \"placeholder\": 'Edit task'};") != null);
    try std.testing.expect(std.mem.indexOf(u8, todo_item_js, "const resolved = scope.handleToggle;") != null);
    try std.testing.expect(std.mem.indexOf(u8, todo_item_js, "refs[5].setProps({\"editing\": true, \"initialValue\": scope.props.todo.title, \"placeholder\": 'Edit task'});") != null);
    try std.testing.expect(std.mem.indexOf(u8, todo_item_js, "refs[5].setEventHandlers({\"cancel\": (payload) => runOwnedBoundary(instance, () => { const resolved = scope.handleCancel;") != null);
    try std.testing.expect(std.mem.indexOf(u8, todo_item_js, "const next = Boolean(scope.props.editing);") != null);
    try std.testing.expect(std.mem.indexOf(u8, todo_item_js, "const __value_11_class = scope.itemClass();") != null);

    const loop_source =
        \\<template>
        \\  <Shell #for="item in items"></Shell>
        \\</template>
        \\
        \\<script lang="ts">
        \\  import Shell from "./Shell.weiv";
        \\  export interface Props {}
        \\  export let props: Props;
        \\  let items = [1, 2, 3];
        \\</script>
    ;

    var loop_model = try compiler_compile.compile(loop_source, "inline-static-loop-child.weiv", allocator);
    defer loop_model.deinit(allocator);

    const loop_js = try emitComponentJs(&loop_model, allocator);
    defer allocator.free(loop_js);

    try std.testing.expect(std.mem.indexOf(u8, loop_js, "Shell.mountIntoBoundary(start, end, undefined, undefined, undefined);") != null);
    try std.testing.expect(std.mem.indexOf(u8, loop_js, "record.handle.setProps(") == null);
    try std.testing.expect(std.mem.indexOf(u8, loop_js, "record.handle.setEventHandlers(") == null);
    try std.testing.expect(std.mem.indexOf(u8, loop_js, "record.handle.setSlots(") == null);
    try std.testing.expect(std.mem.indexOf(u8, loop_js, "record.handle.update();") == null);
}

test "todomvc direct app emit emits browser-direct entry files" {
    const allocator = std.testing.allocator;
    var tmp_dir = std.testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    const tmp_root = try std.fs.path.join(allocator, &.{ ".zig-cache", "tmp", tmp_dir.sub_path[0..] });
    defer allocator.free(tmp_root);
    const out_dir = try std.fs.path.join(allocator, &.{ tmp_root, "direct-bundle" });
    defer allocator.free(out_dir);

    try app_emit.emitAppLegacy("test/examples/todomvc/App.weiv", out_dir, allocator);

    const bundle_js = try tmp_dir.dir.readFileAlloc(std.Io.Threaded.global_single_threaded.io(), "direct-bundle/bundle.mjs", allocator, .limited(1024 * 1024));
    defer allocator.free(bundle_js);
    const main_js = try tmp_dir.dir.readFileAlloc(std.Io.Threaded.global_single_threaded.io(), "direct-bundle/main.mjs", allocator, .limited(1024 * 1024));
    defer allocator.free(main_js);

    try std.testing.expect(std.mem.indexOf(u8, bundle_js, "export function mount(target, props = {})") != null);
    try std.testing.expect(std.mem.indexOf(u8, bundle_js, "Root.mount(target, props)") != null);
    try std.testing.expect(std.mem.indexOf(u8, bundle_js, "export const components = {") != null);
    try std.testing.expect(std.mem.indexOf(u8, main_js, "WeivApp.mount(target, props);") != null);
}

test "imported helper render module preserves runtime JS imports" {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const source = try readFixture(allocator, "test/examples/imported-helper/App.weiv");
    defer allocator.free(source);

    var model = try compiler_compile.compile(source, "test/examples/imported-helper/App.weiv", allocator);
    defer model.deinit(allocator);

    const js = try emitComponentJs(&model, allocator);
    defer allocator.free(js);

    try std.testing.expect(std.mem.indexOf(u8, js, "import { formatTitle as __weiv_import_formatTitle } from \"./format.js\";") != null);
    try std.testing.expect(std.mem.indexOf(u8, js, "formatTitle(") != null);
}

test "imported TS helper render module rewrites runtime imports to JS" {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const source = try readFixture(allocator, "test/examples/imported-ts-helper/App.weiv");
    defer allocator.free(source);

    var model = try compiler_compile.compile(source, "test/examples/imported-ts-helper/App.weiv", allocator);
    defer model.deinit(allocator);

    const js = try emitComponentJs(&model, allocator);
    defer allocator.free(js);

    try std.testing.expect(std.mem.indexOf(u8, js, "import { formatTitle as __weiv_import_formatTitle } from \"./format.js\";") != null);
    try std.testing.expect(std.mem.indexOf(u8, js, "formatTitle(") != null);
}

test "basic counter emits scoped CSS" {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const source = try readFixture(allocator, "test/examples/basic/basic-counter.weiv");
    defer allocator.free(source);

    var model = try compiler_compile.compile(source, "test/examples/basic/basic-counter.weiv", allocator);
    defer model.deinit(allocator);

    const scope_id = try style.scopeIdForPath(model.source_path, allocator);
    defer allocator.free(scope_id);
    const css = try style.emitScopedCss(&model, allocator);
    defer allocator.free(css);

    const expected_prefix = try std.fmt.allocPrint(allocator, "[data-weiv-scope=\"{s}\"] .counter-card", .{scope_id});
    defer allocator.free(expected_prefix);

    try std.testing.expect(std.mem.indexOf(u8, css, expected_prefix) != null);
    try std.testing.expect(std.mem.indexOf(u8, css, "border-radius: 16px;") != null);
}

test "global style selectors bypass component scoping" {
    const allocator = std.testing.allocator;
    const source =
        \\<template><main class="shell">Global shell</main></template>
        \\<script lang="ts"></script>
        \\<style>
        \\  :global(:root), :global(body) { margin: 0; }
        \\  .shell { display: block; }
        \\</style>
    ;

    var model = try compiler_compile.compile(source, "test/examples/global-style.weiv", allocator);
    defer model.deinit(allocator);

    const scope_id = try style.scopeIdForPath(model.source_path, allocator);
    defer allocator.free(scope_id);
    const css = try style.emitScopedCss(&model, allocator);
    defer allocator.free(css);

    try std.testing.expect(std.mem.indexOf(u8, css, ":root, body { margin: 0; }") != null);
    try std.testing.expect(std.mem.indexOf(u8, css, ":global(") == null);
    const expected_scoped = try std.fmt.allocPrint(allocator, "[data-weiv-scope=\"{s}\"] .shell", .{scope_id});
    defer allocator.free(expected_scoped);
    try std.testing.expect(std.mem.indexOf(u8, css, expected_scoped) != null);
}

test "bare element style selectors keep valid scoped combinators" {
    const allocator = std.testing.allocator;
    const source =
        \\<template><header><button>Hello</button></header></template>
        \\<script lang="ts"></script>
        \\<style>
        \\  button, input, textarea { font: inherit; }
        \\  header:hover { display: flex; }
        \\</style>
    ;

    var model = try compiler_compile.compile(source, "test/examples/bare-element-style.weiv", allocator);
    defer model.deinit(allocator);

    const scope_id = try style.scopeIdForPath(model.source_path, allocator);
    defer allocator.free(scope_id);
    const css = try style.emitScopedCss(&model, allocator);
    defer allocator.free(css);

    const invalid_button = try std.fmt.allocPrint(allocator, "[data-weiv-scope=\"{s}\"]button", .{scope_id});
    defer allocator.free(invalid_button);
    try std.testing.expect(std.mem.indexOf(u8, css, invalid_button) == null);

    const root_button = try std.fmt.allocPrint(allocator, "button[data-weiv-scope=\"{s}\"]", .{scope_id});
    defer allocator.free(root_button);
    const descendant_button = try std.fmt.allocPrint(allocator, "[data-weiv-scope=\"{s}\"] button", .{scope_id});
    defer allocator.free(descendant_button);
    const root_header_hover = try std.fmt.allocPrint(allocator, "header[data-weiv-scope=\"{s}\"]:hover", .{scope_id});
    defer allocator.free(root_header_hover);
    try std.testing.expect(std.mem.indexOf(u8, css, root_button) != null);
    try std.testing.expect(std.mem.indexOf(u8, css, descendant_button) != null);
    try std.testing.expect(std.mem.indexOf(u8, css, root_header_hover) != null);
}

test "classic todo app emits multi-file app emit" {
    const allocator = std.testing.allocator;
    var tmp_dir = std.testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    const tmp_root = try std.fs.path.join(allocator, &.{ ".zig-cache", "tmp", tmp_dir.sub_path[0..] });
    defer allocator.free(tmp_root);
    const out_dir = try std.fs.path.join(allocator, &.{ tmp_root, "bundle" });
    defer allocator.free(out_dir);

    try app_emit.emitAppLegacy("test/examples/classic-todo/App.weiv", out_dir, allocator);

    const app_js = try tmp_dir.dir.readFileAlloc(std.Io.Threaded.global_single_threaded.io(), "bundle/bundle.mjs", allocator, .limited(1024 * 1024));
    defer allocator.free(app_js);
    const browser_entry_js = try tmp_dir.dir.readFileAlloc(std.Io.Threaded.global_single_threaded.io(), "bundle/main.mjs", allocator, .limited(1024 * 1024));
    defer allocator.free(browser_entry_js);
    const props_js = try tmp_dir.dir.readFileAlloc(std.Io.Threaded.global_single_threaded.io(), "bundle/props.mjs", allocator, .limited(1024 * 1024));
    defer allocator.free(props_js);
    const index_html = try tmp_dir.dir.readFileAlloc(std.Io.Threaded.global_single_threaded.io(), "bundle/index.html", allocator, .limited(1024 * 1024));
    defer allocator.free(index_html);
    const package_json = try tmp_dir.dir.readFileAlloc(std.Io.Threaded.global_single_threaded.io(), "bundle/package.json", allocator, .limited(1024 * 1024));
    defer allocator.free(package_json);
    const dev_server_ts = try tmp_dir.dir.readFileAlloc(std.Io.Threaded.global_single_threaded.io(), "bundle/server.ts", allocator, .limited(1024 * 1024));
    defer allocator.free(dev_server_ts);
    const root_module_js = try tmp_dir.dir.readFileAlloc(std.Io.Threaded.global_single_threaded.io(), "bundle/App.mjs", allocator, .limited(1024 * 1024));
    defer allocator.free(root_module_js);
    const list_module_js = try tmp_dir.dir.readFileAlloc(std.Io.Threaded.global_single_threaded.io(), "bundle/TodoList.mjs", allocator, .limited(1024 * 1024));
    defer allocator.free(list_module_js);
    const styles_css = try tmp_dir.dir.readFileAlloc(std.Io.Threaded.global_single_threaded.io(), "bundle/styles.css", allocator, .limited(1024 * 1024));
    defer allocator.free(styles_css);

    try std.testing.expect(std.mem.indexOf(u8, app_js, "\"TodoList\": Component_") != null);
    try std.testing.expect(std.mem.indexOf(u8, app_js, "\"TodoItem\": Component_") != null);
    try std.testing.expect(std.mem.indexOf(u8, browser_entry_js, "import { props as previewProps } from \"./props.mjs\";") != null);
    try std.testing.expect(std.mem.indexOf(u8, browser_entry_js, "const props = globalThis.__WEIV_PROPS__ ?? previewProps;") != null);
    try std.testing.expect(std.mem.indexOf(u8, browser_entry_js, "WeivApp.mount(target, props);") != null);
    try std.testing.expect(std.mem.indexOf(u8, props_js, "export const props = { title: \"Preview\" };") != null);
    try std.testing.expect(std.mem.indexOf(u8, index_html, "<link rel=\"stylesheet\" href=\"/styles.css\" />") != null);
    try std.testing.expect(std.mem.indexOf(u8, index_html, "<script type=\"module\" src=\"/main.mjs\"></script>") != null);
    try std.testing.expect(std.mem.indexOf(u8, package_json, "\"dev\": \"bun --hot server.ts\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, package_json, "\"start\": \"bun server.ts\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, dev_server_ts, "const server = Bun.serve({") != null);
    try std.testing.expect(std.mem.indexOf(u8, dev_server_ts, "pathname === \"/\" ? \"/index.html\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, dev_server_ts, "new URL(\"./index.html\", import.meta.url)") != null);
    try std.testing.expect(std.mem.indexOf(u8, app_js, "export function mount(target, props = {})") != null);
    try std.testing.expect(std.mem.indexOf(u8, app_js, "Root.mount(target, props)") != null);
    try std.testing.expect(std.mem.indexOf(u8, list_module_js, "export const css = ") != null);
    try std.testing.expect(std.mem.indexOf(u8, styles_css, "[data-weiv-scope=") != null);
    try std.testing.expect(std.mem.indexOf(u8, styles_css, ".todo-app") != null);
    try std.testing.expect(std.mem.indexOf(u8, styles_css, ".todo-list") != null);
    try std.testing.expect(std.mem.indexOf(u8, styles_css, ".todo-item") != null);
}

test "todomvc verification app emits multi-file app emit" {
    const allocator = std.testing.allocator;
    var tmp_dir = std.testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    const tmp_root = try std.fs.path.join(allocator, &.{ ".zig-cache", "tmp", tmp_dir.sub_path[0..] });
    defer allocator.free(tmp_root);
    const out_dir = try std.fs.path.join(allocator, &.{ tmp_root, "todomvc-bundle" });
    defer allocator.free(out_dir);

    try app_emit.emitAppLegacy("test/examples/todomvc/App.weiv", out_dir, allocator);

    const app_js = try tmp_dir.dir.readFileAlloc(std.Io.Threaded.global_single_threaded.io(), "todomvc-bundle/bundle.mjs", allocator, .limited(1024 * 1024));
    defer allocator.free(app_js);
    const props_js = try tmp_dir.dir.readFileAlloc(std.Io.Threaded.global_single_threaded.io(), "todomvc-bundle/props.mjs", allocator, .limited(1024 * 1024));
    defer allocator.free(props_js);
    const expected_props_js = try readFixture(allocator, "test/fixtures/expected/todomvc-app/props.mjs");
    defer allocator.free(expected_props_js);
    const browser_entry_js = try tmp_dir.dir.readFileAlloc(std.Io.Threaded.global_single_threaded.io(), "todomvc-bundle/main.mjs", allocator, .limited(1024 * 1024));
    defer allocator.free(browser_entry_js);
    const expected_browser_entry_js = try readFixture(allocator, "test/fixtures/expected/todomvc-app/main.mjs");
    defer allocator.free(expected_browser_entry_js);
    const index_html = try tmp_dir.dir.readFileAlloc(std.Io.Threaded.global_single_threaded.io(), "todomvc-bundle/index.html", allocator, .limited(1024 * 1024));
    defer allocator.free(index_html);
    const expected_index_html = try readFixture(allocator, "test/fixtures/expected/todomvc-app/index.html");
    defer allocator.free(expected_index_html);
    const package_json = try tmp_dir.dir.readFileAlloc(std.Io.Threaded.global_single_threaded.io(), "todomvc-bundle/package.json", allocator, .limited(1024 * 1024));
    defer allocator.free(package_json);
    const expected_package_json = try readFixture(allocator, "test/fixtures/expected/todomvc-app/package.json");
    defer allocator.free(expected_package_json);
    const dev_server_ts = try tmp_dir.dir.readFileAlloc(std.Io.Threaded.global_single_threaded.io(), "todomvc-bundle/server.ts", allocator, .limited(1024 * 1024));
    defer allocator.free(dev_server_ts);
    const expected_dev_server_ts = try readFixture(allocator, "test/fixtures/expected/todomvc-app/server.ts");
    defer allocator.free(expected_dev_server_ts);
    const root_module_js = try tmp_dir.dir.readFileAlloc(std.Io.Threaded.global_single_threaded.io(), "todomvc-bundle/App.mjs", allocator, .limited(1024 * 1024));
    defer allocator.free(root_module_js);
    const header_module_js = try tmp_dir.dir.readFileAlloc(std.Io.Threaded.global_single_threaded.io(), "todomvc-bundle/TodoHeader.mjs", allocator, .limited(1024 * 1024));
    defer allocator.free(header_module_js);
    const footer_module_js = try tmp_dir.dir.readFileAlloc(std.Io.Threaded.global_single_threaded.io(), "todomvc-bundle/TodoFooter.mjs", allocator, .limited(1024 * 1024));
    defer allocator.free(footer_module_js);
    const list_module_js = try tmp_dir.dir.readFileAlloc(std.Io.Threaded.global_single_threaded.io(), "todomvc-bundle/TodoList.mjs", allocator, .limited(1024 * 1024));
    defer allocator.free(list_module_js);
    const item_module_js = try tmp_dir.dir.readFileAlloc(std.Io.Threaded.global_single_threaded.io(), "todomvc-bundle/TodoItem.mjs", allocator, .limited(1024 * 1024));
    defer allocator.free(item_module_js);
    const text_input_module_js = try tmp_dir.dir.readFileAlloc(std.Io.Threaded.global_single_threaded.io(), "todomvc-bundle/TodoTextInput.mjs", allocator, .limited(1024 * 1024));
    defer allocator.free(text_input_module_js);
    const styles_css = try tmp_dir.dir.readFileAlloc(std.Io.Threaded.global_single_threaded.io(), "todomvc-bundle/styles.css", allocator, .limited(1024 * 1024));
    defer allocator.free(styles_css);

    try std.testing.expectEqualStrings(expected_browser_entry_js, browser_entry_js);
    try std.testing.expectEqualStrings(expected_props_js, props_js);
    try std.testing.expectEqualStrings(expected_index_html, index_html);
    try std.testing.expectEqualStrings(expected_package_json, package_json);
    try std.testing.expectEqualStrings(expected_dev_server_ts, dev_server_ts);
    try std.testing.expect(std.mem.indexOf(u8, app_js, "export function mount(target, props = {})") != null);
    try std.testing.expect(std.mem.indexOf(u8, app_js, "Root.mount(target, props)") != null);
    try std.testing.expect(std.mem.indexOf(u8, app_js, "\"TodoHeader\": Component_") != null);
    try std.testing.expect(std.mem.indexOf(u8, app_js, "\"TodoList\": Component_") != null);
    try std.testing.expect(std.mem.indexOf(u8, app_js, "\"TodoFooter\": Component_") != null);
    try std.testing.expect(std.mem.indexOf(u8, root_module_js, "toggle-all") != null);
    try std.testing.expect(std.mem.indexOf(u8, header_module_js, "What needs to be done?") != null);
    try std.testing.expect(std.mem.indexOf(u8, footer_module_js, "Clear completed") != null);
    try std.testing.expect(std.mem.indexOf(u8, list_module_js, "todo-list") != null);
    try std.testing.expect(std.mem.indexOf(u8, item_module_js, "destroy") != null);
    try std.testing.expect(std.mem.indexOf(u8, text_input_module_js, "emit(\"submit\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, styles_css, ".todo-header") != null);
    try std.testing.expect(std.mem.indexOf(u8, styles_css, ".todo-footer") != null);
    try std.testing.expect(std.mem.indexOf(u8, styles_css, ".toggle-all") != null);
    try std.testing.expect(std.mem.indexOf(u8, styles_css, ".newtodo") != null);
}

test "kanib app emits multi-file app emit" {
    const allocator = std.testing.allocator;
    var tmp_dir = std.testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    const tmp_root = try std.fs.path.join(allocator, &.{ ".zig-cache", "tmp", tmp_dir.sub_path[0..] });
    defer allocator.free(tmp_root);
    const out_dir = try std.fs.path.join(allocator, &.{ tmp_root, "kanib-bundle" });
    defer allocator.free(out_dir);

    try app_emit.emitAppLegacy("test/examples/kanib/App.weiv", out_dir, allocator);

    const bundle_js = try tmp_dir.dir.readFileAlloc(std.Io.Threaded.global_single_threaded.io(), "kanib-bundle/bundle.mjs", allocator, .limited(1024 * 1024));
    defer allocator.free(bundle_js);
    const root_module_js = try tmp_dir.dir.readFileAlloc(std.Io.Threaded.global_single_threaded.io(), "kanib-bundle/App.mjs", allocator, .limited(1024 * 1024));
    defer allocator.free(root_module_js);
    const shared_module_js = try tmp_dir.dir.readFileAlloc(std.Io.Threaded.global_single_threaded.io(), "kanib-bundle/state/workspace.js", allocator, .limited(1024 * 1024));
    defer allocator.free(shared_module_js);
    const observable_module_js = try tmp_dir.dir.readFileAlloc(std.Io.Threaded.global_single_threaded.io(), "kanib-bundle/__weiv_runtime/index.js", allocator, .limited(1024 * 1024));
    defer allocator.free(observable_module_js);
    const observable_leaf_module_js = try tmp_dir.dir.readFileAlloc(std.Io.Threaded.global_single_threaded.io(), "kanib-bundle/__weiv_runtime/observable.js", allocator, .limited(1024 * 1024));
    defer allocator.free(observable_leaf_module_js);
    const metric_tone_js = try tmp_dir.dir.readFileAlloc(std.Io.Threaded.global_single_threaded.io(), "kanib-bundle/utils/metric_tone.js", allocator, .limited(1024 * 1024));
    defer allocator.free(metric_tone_js);
    const header_module_js = try tmp_dir.dir.readFileAlloc(std.Io.Threaded.global_single_threaded.io(), "kanib-bundle/components/WorkspaceHeader.mjs", allocator, .limited(1024 * 1024));
    defer allocator.free(header_module_js);
    const detail_module_js = try tmp_dir.dir.readFileAlloc(std.Io.Threaded.global_single_threaded.io(), "kanib-bundle/components/DetailPanel.mjs", allocator, .limited(1024 * 1024));
    defer allocator.free(detail_module_js);
    const styles_css = try tmp_dir.dir.readFileAlloc(std.Io.Threaded.global_single_threaded.io(), "kanib-bundle/styles.css", allocator, .limited(1024 * 1024));
    defer allocator.free(styles_css);

    try std.testing.expect(std.mem.indexOf(u8, bundle_js, "export function mount(target, props = {})") != null);
    try std.testing.expect(std.mem.indexOf(u8, bundle_js, "\"WorkspaceHeader\": Component_") != null);
    try std.testing.expect(std.mem.indexOf(u8, bundle_js, "\"IssueListPage\": Component_") != null);
    try std.testing.expect(std.mem.indexOf(u8, bundle_js, "\"OverviewPage\": Component_") != null);
    try std.testing.expect(std.mem.indexOf(u8, bundle_js, "\"DetailPanel\": Component_") != null);
    try std.testing.expect(std.mem.indexOf(u8, root_module_js, "queueMicrotask") != null);
    try std.testing.expect(std.mem.indexOf(u8, root_module_js, "registerExternalSaveListener") != null);
    try std.testing.expect(std.mem.indexOf(u8, root_module_js, "./__weiv_runtime/router.js") != null);
    try std.testing.expect(std.mem.indexOf(u8, shared_module_js, "export const workspaceShared") != null);
    try std.testing.expect(std.mem.indexOf(u8, shared_module_js, "import { observable } from \"../__weiv_runtime/observable.js\";") != null);
    try std.testing.expect(std.mem.indexOf(u8, shared_module_js, "export const workspaceShared = observable({") != null);
    try std.testing.expect(std.mem.indexOf(u8, shared_module_js, "emitExternalSavePulse") != null);
    try std.testing.expect(std.mem.indexOf(u8, observable_module_js, "export { observable } from \"./observable.js\";") != null);
    try std.testing.expect(std.mem.indexOf(u8, observable_leaf_module_js, "const WEIV_OBSERVABLE = Symbol.for(\"weiv.observable\");") != null);
    try std.testing.expect(std.mem.indexOf(u8, metric_tone_js, "metric-card--up") != null);
    try std.testing.expect(std.mem.indexOf(u8, header_module_js, "Sync updates") != null);
    try std.testing.expect(std.mem.indexOf(u8, detail_module_js, "Start live sync") != null);
    try std.testing.expect(std.mem.indexOf(u8, styles_css, ".workspace-shell") != null);
    try std.testing.expect(std.mem.indexOf(u8, styles_css, ".workspace-header") != null);
    try std.testing.expect(std.mem.indexOf(u8, styles_css, ".activity-feed__list") != null);
    try std.testing.expect(std.mem.indexOf(u8, styles_css, ".detail-panel__content") != null);
}

test "basic counter app emit emits inferred preview props" {
    const allocator = std.testing.allocator;
    var tmp_dir = std.testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    const tmp_root = try std.fs.path.join(allocator, &.{ ".zig-cache", "tmp", tmp_dir.sub_path[0..] });
    defer allocator.free(tmp_root);
    const out_dir = try std.fs.path.join(allocator, &.{ tmp_root, "counter-bundle" });
    defer allocator.free(out_dir);

    try app_emit.emitAppLegacy("test/examples/basic/basic-counter.weiv", out_dir, allocator);

    const props_js = try tmp_dir.dir.readFileAlloc(std.Io.Threaded.global_single_threaded.io(), "counter-bundle/props.mjs", allocator, .limited(1024 * 1024));
    defer allocator.free(props_js);
    try std.testing.expect(std.mem.indexOf(u8, props_js, "title: \"Preview\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, props_js, "initialCount: 0") != null);
}

test "imported helper app emit copies runtime JS dependencies" {
    const allocator = std.testing.allocator;
    var tmp_dir = std.testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    const tmp_root = try std.fs.path.join(allocator, &.{ ".zig-cache", "tmp", tmp_dir.sub_path[0..] });
    defer allocator.free(tmp_root);
    const out_dir = try std.fs.path.join(allocator, &.{ tmp_root, "imported-helper-bundle" });
    defer allocator.free(out_dir);

    try app_emit.emitAppLegacy("test/examples/imported-helper/App.weiv", out_dir, allocator);

    const app_js = try tmp_dir.dir.readFileAlloc(std.Io.Threaded.global_single_threaded.io(), "imported-helper-bundle/App.mjs", allocator, .limited(1024 * 1024));
    defer allocator.free(app_js);
    const helper_js = try tmp_dir.dir.readFileAlloc(std.Io.Threaded.global_single_threaded.io(), "imported-helper-bundle/format.js", allocator, .limited(1024 * 1024));
    defer allocator.free(helper_js);
    const punctuation_js = try tmp_dir.dir.readFileAlloc(std.Io.Threaded.global_single_threaded.io(), "imported-helper-bundle/punctuation.js", allocator, .limited(1024 * 1024));
    defer allocator.free(punctuation_js);
    const props_js = try tmp_dir.dir.readFileAlloc(std.Io.Threaded.global_single_threaded.io(), "imported-helper-bundle/props.mjs", allocator, .limited(1024 * 1024));
    defer allocator.free(props_js);

    try std.testing.expect(std.mem.indexOf(u8, app_js, "import { formatTitle as __weiv_import_formatTitle } from \"./format.js\";") != null);
    try std.testing.expect(std.mem.indexOf(u8, helper_js, "import { suffix } from \"./punctuation.js\";") != null);
    try std.testing.expect(std.mem.indexOf(u8, helper_js, "export function formatTitle") != null);
    try std.testing.expect(std.mem.indexOf(u8, punctuation_js, "export const suffix = \"!\";") != null);
    try std.testing.expect(std.mem.indexOf(u8, props_js, "title: \"Preview\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, props_js, "count: 0") != null);
}

test "imported TS helper app emit transpiles and copies TS dependencies" {
    const allocator = std.testing.allocator;
    var tmp_dir = std.testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    const tmp_root = try std.fs.path.join(allocator, &.{ ".zig-cache", "tmp", tmp_dir.sub_path[0..] });
    defer allocator.free(tmp_root);
    const out_dir = try std.fs.path.join(allocator, &.{ tmp_root, "imported-ts-helper-bundle" });
    defer allocator.free(out_dir);

    try app_emit.emitAppLegacy("test/examples/imported-ts-helper/App.weiv", out_dir, allocator);

    const app_js = try tmp_dir.dir.readFileAlloc(std.Io.Threaded.global_single_threaded.io(), "imported-ts-helper-bundle/App.mjs", allocator, .limited(1024 * 1024));
    defer allocator.free(app_js);
    const format_js = try tmp_dir.dir.readFileAlloc(std.Io.Threaded.global_single_threaded.io(), "imported-ts-helper-bundle/format.js", allocator, .limited(1024 * 1024));
    defer allocator.free(format_js);
    const punctuation_js = try tmp_dir.dir.readFileAlloc(std.Io.Threaded.global_single_threaded.io(), "imported-ts-helper-bundle/punctuation.js", allocator, .limited(1024 * 1024));
    defer allocator.free(punctuation_js);
    const props_js = try tmp_dir.dir.readFileAlloc(std.Io.Threaded.global_single_threaded.io(), "imported-ts-helper-bundle/props.mjs", allocator, .limited(1024 * 1024));
    defer allocator.free(props_js);

    try std.testing.expect(std.mem.indexOf(u8, app_js, "import { formatTitle as __weiv_import_formatTitle } from \"./format.js\";") != null);
    try std.testing.expect(std.mem.indexOf(u8, format_js, "import { suffix } from \"./punctuation.js\";") != null);
    try std.testing.expect(std.mem.indexOf(u8, format_js, "export function formatTitle(value)") != null);
    try std.testing.expect(std.mem.indexOf(u8, punctuation_js, "export const suffix = \"!\";") != null);
    try std.testing.expect(std.mem.indexOf(u8, props_js, "title: \"Preview\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, props_js, "count: 0") != null);
}

test "emit app rewrites bare imports for strict CSP" {
    const allocator = std.testing.allocator;
    var tmp_dir = std.testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    const tmp_root = try std.fs.path.join(allocator, &.{ ".zig-cache", "tmp", tmp_dir.sub_path[0..] });
    defer allocator.free(tmp_root);
    const out_dir = try std.fs.path.join(allocator, &.{ tmp_root, "bare-import-bundle" });
    defer allocator.free(out_dir);

    try app_emit.emitAppLegacy("test/examples/bare-import/App.weiv", out_dir, allocator);

    const dir = try std.Io.Dir.cwd().openDir(std.Io.Threaded.global_single_threaded.io(), out_dir, .{});
    const html = try dir.readFileAlloc(std.Io.Threaded.global_single_threaded.io(), "index.html", allocator, .limited(64 * 1024));
    defer allocator.free(html);
    const app_js = try dir.readFileAlloc(std.Io.Threaded.global_single_threaded.io(), "App.mjs", allocator, .limited(1024 * 1024));
    defer allocator.free(app_js);
    const server_ts = try dir.readFileAlloc(std.Io.Threaded.global_single_threaded.io(), "server.ts", allocator, .limited(1024 * 1024));
    defer allocator.free(server_ts);

    try std.testing.expect(std.mem.indexOf(u8, html, "importmap") == null);
    try std.testing.expect(std.mem.indexOf(u8, app_js, "from \"/__weiv_packages/lodash-es\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, server_ts, "Bun.resolveSync(specifier, import.meta.dir)") != null);
    try std.testing.expect(std.mem.indexOf(u8, server_ts, "Bun.build({ entrypoints: [entrypoint], target: \"browser\", format: \"esm\" })") != null);
}

test "validate app reports unsupported absolute runtime import with source location" {
    const allocator = std.testing.allocator;
    var temp_dir = std.testing.tmpDir(.{});
    defer temp_dir.cleanup();

    try temp_dir.dir.writeFile(std.Io.Threaded.global_single_threaded.io(), .{
        .sub_path = "App.weiv",
        .data =
        \\<template>
        \\  <p>{{ props.title }}</p>
        \\</template>
        \\
        \\<script lang="ts">
        \\  import { value } from "/tmp/nope.js";
        \\  export interface Props { title: string }
        \\  export let props: Props;
        \\</script>
        ,
    });

    const root = try std.fs.path.join(allocator, &.{ ".zig-cache", "tmp", temp_dir.sub_path[0..], "App.weiv" });
    defer allocator.free(root);

    var report = try app_emit.validateApp(root, allocator);
    defer report.deinit(allocator);

    try std.testing.expectEqual(@as(usize, 1), report.diagnostics.len);
    const diagnostic = report.diagnostics[0];
    try std.testing.expectEqualStrings("import.unsupported_absolute_runtime_import", diagnostic.code);
    try std.testing.expect(diagnostic.fatal);
    try std.testing.expect(diagnostic.location != null);

    const formatted = try cli.formatAppValidationDiagnostics(root, report.diagnostics, allocator);
    defer allocator.free(formatted);
    try std.testing.expect(std.mem.indexOf(u8, formatted, "weiv validate app failed for") != null);
    try std.testing.expect(std.mem.indexOf(u8, formatted, "error import.unsupported_absolute_runtime_import [bundle]") != null);
}

test "validate app reports unsupported relative runtime import type with source location" {
    const allocator = std.testing.allocator;
    var temp_dir = std.testing.tmpDir(.{});
    defer temp_dir.cleanup();

    try temp_dir.dir.writeFile(std.Io.Threaded.global_single_threaded.io(), .{
        .sub_path = "App.weiv",
        .data =
        \\<template>
        \\  <p>{{ props.title }}</p>
        \\</template>
        \\
        \\<script lang="ts">
        \\  import data from "./data.txt";
        \\  export interface Props { title: string }
        \\  export let props: Props;
        \\</script>
        ,
    });

    try temp_dir.dir.writeFile(std.Io.Threaded.global_single_threaded.io(), .{
        .sub_path = "data.txt",
        .data = "hello",
    });

    const root = try std.fs.path.join(allocator, &.{ ".zig-cache", "tmp", temp_dir.sub_path[0..], "App.weiv" });
    defer allocator.free(root);

    var report = try app_emit.validateApp(root, allocator);
    defer report.deinit(allocator);

    try std.testing.expectEqual(@as(usize, 1), report.diagnostics.len);
    const diagnostic = report.diagnostics[0];
    try std.testing.expectEqualStrings("import.unsupported_runtime_import_type", diagnostic.code);
    try std.testing.expect(diagnostic.fatal);
    try std.testing.expect(diagnostic.location != null);

    const formatted = try cli.formatAppValidationDiagnostics(root, report.diagnostics, allocator);
    defer allocator.free(formatted);
    try std.testing.expect(std.mem.indexOf(u8, formatted, "error import.unsupported_runtime_import_type [bundle]") != null);
}

test "validate app can format machine-readable json diagnostics" {
    const allocator = std.testing.allocator;
    var temp_dir = std.testing.tmpDir(.{});
    defer temp_dir.cleanup();

    try temp_dir.dir.writeFile(std.Io.Threaded.global_single_threaded.io(), .{
        .sub_path = "App.weiv",
        .data =
        \\<template>
        \\  <p>{{ props.title }}</p>
        \\</template>
        \\
        \\<script lang="ts">
        \\  import data from "./data.txt";
        \\  export interface Props { title: string }
        \\  export let props: Props;
        \\</script>
        ,
    });

    try temp_dir.dir.writeFile(std.Io.Threaded.global_single_threaded.io(), .{
        .sub_path = "data.txt",
        .data = "hello",
    });

    const root = try std.fs.path.join(allocator, &.{ ".zig-cache", "tmp", temp_dir.sub_path[0..], "App.weiv" });
    defer allocator.free(root);

    var report = try app_emit.validateApp(root, allocator);
    defer report.deinit(allocator);

    const json = try cli.formatAppValidationDiagnosticsJson(root, report.diagnostics, allocator);
    defer allocator.free(json);

    try std.testing.expect(std.mem.indexOf(u8, json, "\"rootPath\":") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"ok\": false") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"code\": \"import.unsupported_runtime_import_type\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"stage\": \"bundle\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"fatal\": true") != null);
}

test "cli failure formatter emits canonical machine-readable diagnostics json" {
    const allocator = std.testing.allocator;
    var bag = compiler_diagnostics.DiagnosticBag.init();
    defer bag.deinit(allocator);

    try bag.appendOwned(
        allocator,
        "cli.read_failed",
        .@"error",
        "read component (FileNotFound)",
        .sfc_parse,
        "/tmp/missing.weiv",
        null,
        null,
        true,
    );

    const diagnostics = try bag.toOwnedSlice(allocator);
    defer {
        for (diagnostics) |*diagnostic| diagnostic.deinit(allocator);
        allocator.free(diagnostics);
    }

    const json = try cli.formatCliFailureDiagnosticsJson("read component", "/tmp/missing.weiv", diagnostics, allocator);
    defer allocator.free(json);

    try std.testing.expect(std.mem.indexOf(u8, json, "\"action\": \"read component\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"sourcePath\": \"/tmp/missing.weiv\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"ok\": false") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"code\": \"cli.read_failed\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"severity\": \"error\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"stage\": \"sfc_parse\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"fatal\": true") != null);
}

test "cli failure formatter json reports ok true when no fatal diagnostics" {
    const allocator = std.testing.allocator;
    var bag = compiler_diagnostics.DiagnosticBag.init();
    defer bag.deinit(allocator);

    try bag.appendOwned(
        allocator,
        "binding.escape_warning",
        .warning,
        "local alias may escape tracked root",
        .binding,
        "test/examples/sample.weiv",
        null,
        null,
        false,
    );

    const diagnostics = try bag.toOwnedSlice(allocator);
    defer {
        for (diagnostics) |*diagnostic| diagnostic.deinit(allocator);
        allocator.free(diagnostics);
    }

    const json = try cli.formatCliFailureDiagnosticsJson("inspect invalidation-graph", "test/examples/sample.weiv", diagnostics, allocator);
    defer allocator.free(json);

    try std.testing.expect(std.mem.indexOf(u8, json, "\"ok\": true") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"severity\": \"warning\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"stage\": \"binding\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"fatal\": false") != null);
}

test "cli failure formatter json keeps stable canonical shape" {
    const allocator = std.testing.allocator;
    var bag = compiler_diagnostics.DiagnosticBag.init();
    defer bag.deinit(allocator);

    try bag.appendOwned(
        allocator,
        "emit.js_failed",
        .@"error",
        "emit js (InvalidTemplate)",
        .emit,
        "test/examples/sample.weiv",
        null,
        null,
        true,
    );

    const diagnostics = try bag.toOwnedSlice(allocator);
    defer {
        for (diagnostics) |*diagnostic| diagnostic.deinit(allocator);
        allocator.free(diagnostics);
    }

    const json = try cli.formatCliFailureDiagnosticsJson("emit js", "test/examples/sample.weiv", diagnostics, allocator);
    defer allocator.free(json);

    const expected =
        \\{
        \\  "action": "emit js",
        \\  "sourcePath": "test/examples/sample.weiv",
        \\  "ok": false,
        \\  "diagnostics": [
        \\    {
        \\      "code": "emit.js_failed",
        \\      "severity": "error",
        \\      "stage": "emit",
        \\      "message": "emit js (InvalidTemplate)",
        \\      "sourcePath": "test/examples/sample.weiv",
        \\      "span": null,
        \\      "location": null,
        \\      "fatal": true
        \\    }
        \\  ]
        \\}
        \\
    ;
    try std.testing.expectEqualStrings(expected, json);
}

test "validate app reports invalid scoped style diagnostics" {
    const allocator = std.testing.allocator;
    var temp_dir = std.testing.tmpDir(.{});
    defer temp_dir.cleanup();

    try temp_dir.dir.writeFile(std.Io.Threaded.global_single_threaded.io(), .{
        .sub_path = "App.weiv",
        .data =
        \\<template>
        \\  <p>{{ props.title }}</p>
        \\</template>
        \\
        \\<script lang="ts">
        \\  export interface Props { title: string }
        \\  export let props: Props;
        \\</script>
        \\
        \\<style>
        \\  .broken {
        \\    color: red;
        \\</style>
        ,
    });

    const root = try std.fs.path.join(allocator, &.{ ".zig-cache", "tmp", temp_dir.sub_path[0..], "App.weiv" });
    defer allocator.free(root);

    var report = try app_emit.validateApp(root, allocator);
    defer report.deinit(allocator);

    try std.testing.expectEqual(@as(usize, 1), report.diagnostics.len);
    const diagnostic = report.diagnostics[0];
    try std.testing.expectEqualStrings("style.unterminated_rule", diagnostic.code);
    try std.testing.expectEqual(.emit, diagnostic.stage);
    try std.testing.expect(diagnostic.fatal);

    const formatted = try cli.formatAppValidationDiagnostics(root, report.diagnostics, allocator);
    defer allocator.free(formatted);
    try std.testing.expect(std.mem.indexOf(u8, formatted, "style.unterminated_rule [emit]") != null);
}

test "validate app reports component build diagnostics for malformed child components" {
    const allocator = std.testing.allocator;
    var temp_dir = std.testing.tmpDir(.{});
    defer temp_dir.cleanup();

    try temp_dir.dir.writeFile(std.Io.Threaded.global_single_threaded.io(), .{
        .sub_path = "App.weiv",
        .data =
        \\<template>
        \\  <Child />
        \\</template>
        \\
        \\<script lang="ts">
        \\  import Child from "./Child.weiv";
        \\  export interface Props {}
        \\  export let props: Props;
        \\</script>
        ,
    });

    try temp_dir.dir.writeFile(std.Io.Threaded.global_single_threaded.io(), .{
        .sub_path = "Child.weiv",
        .data =
        \\<template>
        \\  <div #else>bad</div>
        \\</template>
        \\
        \\<script lang="ts">
        \\  export interface Props {}
        \\  export let props: Props;
        \\</script>
        ,
    });

    const root = try std.fs.path.join(allocator, &.{ ".zig-cache", "tmp", temp_dir.sub_path[0..], "App.weiv" });
    defer allocator.free(root);

    var report = try app_emit.validateApp(root, allocator);
    defer report.deinit(allocator);

    try std.testing.expectEqual(@as(usize, 1), report.diagnostics.len);
    const diagnostic = report.diagnostics[0];
    try std.testing.expectEqualStrings("template.unexpected_else", diagnostic.code);
    try std.testing.expectEqual(.template_normalize, diagnostic.stage);
    try std.testing.expect(diagnostic.fatal);
    try std.testing.expect(std.mem.endsWith(u8, diagnostic.source_path, "Child.weiv"));

    const json = try cli.formatAppValidationDiagnosticsJson(root, report.diagnostics, allocator);
    defer allocator.free(json);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"code\": \"template.unexpected_else\"") != null);
}

test "validate app reports component tag conflicts as structured diagnostics" {
    const allocator = std.testing.allocator;
    var temp_dir = std.testing.tmpDir(.{});
    defer temp_dir.cleanup();

    try temp_dir.dir.createDirPath(std.Io.Threaded.global_single_threaded.io(), "first");
    try temp_dir.dir.createDirPath(std.Io.Threaded.global_single_threaded.io(), "second");

    try temp_dir.dir.writeFile(std.Io.Threaded.global_single_threaded.io(), .{
        .sub_path = "App.weiv",
        .data =
        \\<template>
        \\  <SectionA />
        \\  <SectionB />
        \\</template>
        \\
        \\<script lang="ts">
        \\  import SectionA from "./SectionA.weiv";
        \\  import SectionB from "./SectionB.weiv";
        \\  export interface Props {}
        \\  export let props: Props;
        \\</script>
        ,
    });

    try temp_dir.dir.writeFile(std.Io.Threaded.global_single_threaded.io(), .{
        .sub_path = "SectionA.weiv",
        .data =
        \\<template><Panel /></template>
        \\<script lang="ts">
        \\  import Panel from "./first/Panel.weiv";
        \\  export interface Props {}
        \\  export let props: Props;
        \\</script>
        ,
    });

    try temp_dir.dir.writeFile(std.Io.Threaded.global_single_threaded.io(), .{
        .sub_path = "SectionB.weiv",
        .data =
        \\<template><Panel /></template>
        \\<script lang="ts">
        \\  import Panel from "./second/Panel.weiv";
        \\  export interface Props {}
        \\  export let props: Props;
        \\</script>
        ,
    });

    try temp_dir.dir.writeFile(std.Io.Threaded.global_single_threaded.io(), .{
        .sub_path = "first/Panel.weiv",
        .data =
        \\<template><p>First</p></template>
        \\<script lang="ts">
        \\  export interface Props {}
        \\  export let props: Props;
        \\</script>
        ,
    });

    try temp_dir.dir.writeFile(std.Io.Threaded.global_single_threaded.io(), .{
        .sub_path = "second/Panel.weiv",
        .data =
        \\<template><p>Second</p></template>
        \\<script lang="ts">
        \\  export interface Props {}
        \\  export let props: Props;
        \\</script>
        ,
    });

    const root = try std.fs.path.join(allocator, &.{ ".zig-cache", "tmp", temp_dir.sub_path[0..], "App.weiv" });
    defer allocator.free(root);

    var report = try app_emit.validateApp(root, allocator);
    defer report.deinit(allocator);

    try std.testing.expectEqual(@as(usize, 1), report.diagnostics.len);
    try std.testing.expectEqualStrings("bundle.component_tag_conflict", report.diagnostics[0].code);
    try std.testing.expectEqual(.bundle, report.diagnostics[0].stage);
    try std.testing.expect(report.diagnostics[0].fatal);

    const json = try cli.formatAppValidationDiagnosticsJson(root, report.diagnostics, allocator);
    defer allocator.free(json);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"code\": \"bundle.component_tag_conflict\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"stage\": \"bundle\"") != null);
}

test "component build report preserves invalid directive diagnostics" {
    const allocator = std.testing.allocator;
    const source =
        \\<template>
        \\  <button on:click>bad</button>
        \\</template>
        \\
        \\<script lang="ts">
        \\  export interface Props {}
        \\  export let props: Props;
        \\</script>
    ;

    var report = try compiler_compile.compileReport(source, "test/examples/invalid-directive-analysis.weiv", allocator);
    defer report.deinit(allocator);

    try std.testing.expect(report.halted_after != null);
    try std.testing.expectEqual(@as(usize, 1), report.diagnostics.len);
    try std.testing.expectEqualStrings("template.invalid_directive", report.diagnostics[0].code);
    try std.testing.expectEqual(.template_parse, report.diagnostics[0].stage);
    try std.testing.expect(report.diagnostics[0].fatal);

    const formatted = try cli.formatComponentCompileReport(report, allocator);
    defer allocator.free(formatted);
    try std.testing.expect(std.mem.indexOf(u8, formatted, "template.invalid_directive [template_parse]") != null);
}

test "component style emit diagnostics report invalid scoped css" {
    const allocator = std.testing.allocator;
    const source =
        \\<template>
        \\  <p>{{ props.title }}</p>
        \\</template>
        \\
        \\<script lang="ts">
        \\  export interface Props { title: string }
        \\  export let props: Props;
        \\</script>
        \\
        \\<style>
        \\  .broken {
        \\    color: red;
        \\</style>
    ;

    var model = try compiler_compile.compile(source, "test/examples/invalid-style-diagnostic.weiv", allocator);
    defer model.deinit(allocator);

    var bag = compiler_diagnostics.DiagnosticBag.init();
    defer bag.deinit(allocator);
    try style.appendEmitDiagnostics(&bag, &model, source, allocator);

    try std.testing.expect(bag.hasFatal());
    try std.testing.expectEqual(@as(usize, 1), bag.diagnostics.items.len);
    try std.testing.expectEqualStrings("style.unterminated_rule", bag.diagnostics.items[0].code);
    try std.testing.expectEqual(.emit, bag.diagnostics.items[0].stage);
}

test "kanib WorkspaceSidebar binding diagnostics stay on helper.external_state warnings" {
    const allocator = std.testing.allocator;
    const source = try readFixture(allocator, "test/examples/kanib/components/WorkspaceSidebar.weiv");
    defer allocator.free(source);

    var model = try compiler_compile.compile(source, "test/examples/kanib/components/WorkspaceSidebar.weiv", allocator);
    defer model.deinit(allocator);

    try std.testing.expectEqual(@as(usize, 2), model.template_bindings.diagnostics.len);
    for (model.template_bindings.diagnostics) |diagnostic| {
        try std.testing.expectEqualStrings("warning", diagnostic.severity);
        try std.testing.expectEqualStrings("helper.external_state", diagnostic.kind);
    }
}

fn expectComponentBuild(
    allocator: std.mem.Allocator,
    source: []const u8,
    path: []const u8,
    expected_component_refs: usize,
    expected_binding_diagnostics: usize,
) !void {
    defer allocator.free(source);
    var model = try compiler_compile.compile(source, path, allocator);
    defer model.deinit(allocator);

    try std.testing.expect(model.script.ok);
    try std.testing.expectEqual(@as(usize, 0), model.script.diagnostics.len);
    try std.testing.expectEqual(expected_component_refs, model.template_bindings.component_refs.len);
    try std.testing.expectEqual(expected_binding_diagnostics, model.template_bindings.diagnostics.len);
}

test "user-defined emit binding reports framework conflict diagnostic" {
    const allocator = std.testing.allocator;
    const source =
        \\<template>
        \\  <button @click="save">{{ props.title }}</button>
        \\</template>
        \\
        \\<script lang="ts">
        \\  export interface Props {
        \\    title: string;
        \\  }
        \\
        \\  export let props: Props;
        \\
        \\  function emit(name: string, payload: unknown) {
        \\    console.log(name, payload);
        \\  }
        \\
        \\  function save() {
        \\    emit("save", props.title);
        \\  }
        \\</script>
    ;

    var model = try compiler_compile.compile(source, "test/examples/framework-emit-conflict.weiv", allocator);
    defer model.deinit(allocator);

    try std.testing.expectEqual(@as(usize, 1), model.template_bindings.diagnostics.len);
    const diagnostic = model.template_bindings.diagnostics[0];
    try std.testing.expectEqualStrings("error", diagnostic.severity);
    try std.testing.expectEqualStrings("framework.reserved_binding", diagnostic.kind);
    try std.testing.expectEqualStrings("emit", diagnostic.name);
    try std.testing.expect(std.mem.indexOf(u8, diagnostic.message, "`emit` is provided by Weiv") != null);
}

test "user-defined weivUpdate binding reports framework conflict diagnostic" {
    const allocator = std.testing.allocator;
    const source =
        \\<template><p>{{ count }}</p></template>
        \\<script lang="ts">
        \\  export interface Props {}
        \\  export let props: Props;
        \\  let count = 0;
        \\  const weivUpdate = (callback: () => void) => callback();
        \\</script>
    ;

    var model = try compiler_compile.compile(source, "test/examples/framework-update-conflict.weiv", allocator);
    defer model.deinit(allocator);

    try std.testing.expectEqual(@as(usize, 1), model.template_bindings.diagnostics.len);
    const diagnostic = model.template_bindings.diagnostics[0];
    try std.testing.expectEqualStrings("error", diagnostic.severity);
    try std.testing.expectEqualStrings("framework.reserved_binding", diagnostic.kind);
    try std.testing.expectEqualStrings("weivUpdate", diagnostic.name);
}

test "template helper with external reads reports conservative diagnostic" {
    const allocator = std.testing.allocator;
    const source =
        \\<template>
        \\  <p>{{ themeLabel() }}</p>
        \\</template>
        \\
        \\<script lang="ts">
        \\  export interface Props {}
        \\  export let props: Props;
        \\
        \\  function themeLabel() {
        \\    return globalThis.__theme?.label ?? "Default";
        \\  }
        \\</script>
    ;

    var model = try compiler_compile.compile(source, "test/examples/helper-external-state-diagnostic.weiv", allocator);
    defer model.deinit(allocator);

    try std.testing.expectEqual(@as(usize, 1), model.template_bindings.diagnostics.len);
    const diagnostic = model.template_bindings.diagnostics[0];
    try std.testing.expectEqualStrings("warning", diagnostic.severity);
    try std.testing.expectEqualStrings("helper.external_state", diagnostic.kind);
    try std.testing.expectEqualStrings("themeLabel", diagnostic.name);
    try std.testing.expect(std.mem.indexOf(u8, diagnostic.message, "reads external state") != null);
}

test "template helper with side effects reports conservative diagnostic" {
    const allocator = std.testing.allocator;
    const source =
        \\<template>
        \\  <p>{{ nextCount() }}</p>
        \\</template>
        \\
        \\<script lang="ts">
        \\  export interface Props {}
        \\  export let props: Props;
        \\
        \\  let count = 0;
        \\
        \\  function nextCount() {
        \\    count += 1;
        \\    return count;
        \\  }
        \\</script>
    ;

    var model = try compiler_compile.compile(source, "test/examples/helper-side-effects-diagnostic.weiv", allocator);
    defer model.deinit(allocator);

    try std.testing.expectEqual(@as(usize, 1), model.template_bindings.diagnostics.len);
    const diagnostic = model.template_bindings.diagnostics[0];
    try std.testing.expectEqualStrings("warning", diagnostic.severity);
    try std.testing.expectEqualStrings("helper.side_effects", diagnostic.kind);
    try std.testing.expectEqualStrings("nextCount", diagnostic.name);
    try std.testing.expect(std.mem.indexOf(u8, diagnostic.message, "has side effects") != null);
}

test "expression-position mutation reports conservative diagnostic" {
    const allocator = std.testing.allocator;
    const source =
        \\<template>
        \\  <button @click="mutate">{{ count }}</button>
        \\</template>
        \\
        \\<script lang="ts">
        \\  export interface Props {}
        \\  export let props: Props;
        \\
        \\  let count = 0;
        \\
        \\  function mutate() {
        \\    const next = count++;
        \\    return next;
        \\  }
        \\</script>
    ;

    var model = try compiler_compile.compile(source, "test/examples/expression-position-mutation-diagnostic.weiv", allocator);
    defer model.deinit(allocator);

    try std.testing.expectEqual(@as(usize, 1), model.template_bindings.diagnostics.len);
    const diagnostic = model.template_bindings.diagnostics[0];
    try std.testing.expectEqualStrings("warning", diagnostic.severity);
    try std.testing.expectEqualStrings("mutation.expression_position", diagnostic.kind);
    try std.testing.expectEqualStrings("count", diagnostic.name);
    try std.testing.expect(std.mem.indexOf(u8, diagnostic.message, "nested inside a larger expression") != null);
}

test "unowned callback mutation reports conservative diagnostic" {
    const allocator = std.testing.allocator;
    const source =
        \\<template>
        \\  <p>{{ count }}</p>
        \\</template>
        \\
        \\<script lang="ts">
        \\  export interface Props {}
        \\  export let props: Props;
        \\
        \\  let count = 0;
        \\
        \\  externalStore.subscribe(() => {
        \\    count += 1;
        \\  });
        \\</script>
    ;

    var model = try compiler_compile.compile(source, "test/examples/unowned-callback-mutation-diagnostic.weiv", allocator);
    defer model.deinit(allocator);

    try std.testing.expectEqual(@as(usize, 1), model.template_bindings.diagnostics.len);
    const diagnostic = model.template_bindings.diagnostics[0];
    try std.testing.expectEqualStrings("warning", diagnostic.severity);
    try std.testing.expectEqualStrings("callback.unowned_mutation", diagnostic.kind);
    try std.testing.expectEqualStrings("count", diagnostic.name);
    try std.testing.expect(std.mem.indexOf(u8, diagnostic.message, "callback boundary that Weiv does not own") != null);
    try std.testing.expect(std.mem.indexOf(u8, diagnostic.message, "without updating the DOM") != null);
    try std.testing.expect(std.mem.indexOf(u8, diagnostic.message, "weivUpdate(() => { ... })") != null);
}

test "external listeners require an explicit owned update boundary" {
    const allocator = std.testing.allocator;
    const source = try readFixture(allocator, "test/examples/basic/external-callback.weiv");
    defer allocator.free(source);

    var model = try compiler_compile.compile(source, "test/examples/basic/external-callback.weiv", allocator);
    defer model.deinit(allocator);

    var unowned_count: usize = 0;
    for (model.template_bindings.diagnostics) |diagnostic| {
        if (std.mem.eql(u8, diagnostic.kind, "callback.unowned_mutation")) unowned_count += 1;
    }
    try std.testing.expectEqual(@as(usize, 1), unowned_count);

    var render_tree = try browser_render_tree.lower(&model.lir_document, allocator);
    defer render_tree.deinit(allocator);
    const formatted = try invalidation_graph.formatDocument(&model, &render_tree, allocator);
    defer allocator.free(formatted);
    try std.testing.expect(std.mem.indexOf(u8, formatted, "callback callee=window.addEventListener kind=inline_arrow owned_candidate=false") != null);
    try std.testing.expect(std.mem.indexOf(u8, formatted, "callback callee=weivUpdate kind=inline_arrow owned_candidate=true") != null);
}

test "alias mutation reports conservative diagnostic" {
    const allocator = std.testing.allocator;
    const source =
        \\<template>
        \\  <p>{{ user.name }}</p>
        \\</template>
        \\
        \\<script lang="ts">
        \\  export interface Props {}
        \\  export let props: Props;
        \\
        \\  let user = { name: "Grace" };
        \\  const alias = user;
        \\
        \\  alias.name = "Ada";
        \\</script>
    ;

    var model = try compiler_compile.compile(source, "test/examples/alias-mutation-diagnostic.weiv", allocator);
    defer model.deinit(allocator);

    try std.testing.expectEqual(@as(usize, 1), model.template_bindings.diagnostics.len);
    const diagnostic = model.template_bindings.diagnostics[0];
    try std.testing.expectEqualStrings("warning", diagnostic.severity);
    try std.testing.expectEqualStrings("alias.mutation", diagnostic.kind);
    try std.testing.expectEqualStrings("user", diagnostic.name);
    try std.testing.expect(std.mem.indexOf(u8, diagnostic.message, "through a local alias") != null);
}

test "component analysis report includes structured script diagnostics" {
    const allocator = std.testing.allocator;
    const source =
        \\<template>
        \\  <p>Hello</p>
        \\</template>
        \\
        \\<script lang="ts">
        \\  const count = 0;
        \\</script>
    ;

    var model = try compiler_compile.compile(source, "test/examples/missing-props-diagnostic.weiv", allocator);
    defer model.deinit(allocator);

    try std.testing.expect(model.script.ok);
    try std.testing.expectEqual(@as(usize, 1), model.script.diagnostics.len);

    const report = try cli.formatComponentAnalysisReport(model, allocator);
    defer allocator.free(report);

    try std.testing.expect(std.mem.indexOf(u8, report, "Script analysis\n  ok: true\n") != null);
    try std.testing.expect(std.mem.indexOf(u8, report, "  diagnostics: 1\n") != null);
    try std.testing.expect(std.mem.indexOf(u8, report, "    - error: Missing `export let props: Props` declaration [0:0] [0..0]\n") != null);
    try std.testing.expect(std.mem.indexOf(u8, report, "Proxy state graph\n  tracked roots: 0\n  root kinds: imported=0 props=0 local=0\n  escape warnings: 0\n") != null);
}

test "component build report preserves fatal template diagnostics" {
    const allocator = std.testing.allocator;
    const source =
        \\<template>
        \\  <div #else>bad</div>
        \\</template>
        \\
        \\<script lang="ts">
        \\  export interface Props {}
        \\  export let props: Props;
        \\</script>
    ;

    var report = try compiler_compile.compileReport(source, "test/examples/unexpected-else-analysis.weiv", allocator);
    defer report.deinit(allocator);

    try std.testing.expect(report.halted_after != null);
    try std.testing.expectEqual(@as(usize, 1), report.diagnostics.len);
    try std.testing.expectEqualStrings("template.unexpected_else", report.diagnostics[0].code);
    try std.testing.expect(report.diagnostics[0].fatal);

    const formatted = try cli.formatComponentCompileReport(report, allocator);
    defer allocator.free(formatted);

    try std.testing.expect(std.mem.indexOf(u8, formatted, "Compiler diagnostics\n  total: 1\n") != null);
    try std.testing.expect(std.mem.indexOf(u8, formatted, "template.unexpected_else [template_normalize]") != null);
    try std.testing.expect(std.mem.indexOf(u8, formatted, "Pipeline halt\n  halted after: template_normalize\n") != null);
}

test "component build report can format machine-readable json diagnostics" {
    const allocator = std.testing.allocator;
    const source =
        \\<template>
        \\  <div #else>bad</div>
        \\</template>
        \\
        \\<script lang="ts">
        \\  export interface Props {}
        \\  export let props: Props;
        \\</script>
    ;

    var report = try compiler_compile.compileReport(source, "test/examples/unexpected-else-analysis-json.weiv", allocator);
    defer report.deinit(allocator);

    const json = try cli.formatComponentCompileReportJson(report, allocator);
    defer allocator.free(json);

    try std.testing.expect(std.mem.indexOf(u8, json, "\"sourcePath\": \"test/examples/unexpected-else-analysis-json.weiv\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"haltedAfter\": \"template_normalize\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"code\": \"template.unexpected_else\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"severity\": \"error\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"stage\": \"template_normalize\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"fatal\": true") != null);
}

test "component build report json includes invalid directive diagnostics" {
    const allocator = std.testing.allocator;
    const source =
        \\<template>
        \\  <button on:click>bad</button>
        \\</template>
        \\
        \\<script lang="ts">
        \\  export interface Props {}
        \\  export let props: Props;
        \\</script>
    ;

    var report = try compiler_compile.compileReport(source, "test/examples/invalid-directive-analysis-json.weiv", allocator);
    defer report.deinit(allocator);

    const json = try cli.formatComponentCompileReportJson(report, allocator);
    defer allocator.free(json);

    try std.testing.expect(std.mem.indexOf(u8, json, "\"code\": \"template.invalid_directive\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"stage\": \"template_parse\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"fatal\": true") != null);
}

test "component analysis report includes tracked root and escape warning summary" {
    const allocator = std.testing.allocator;
    const source =
        \\<template>
        \\  <p>{{ workspace.profile.name }}</p>
        \\</template>
        \\
        \\<script lang="ts">
        \\  import { workspace } from "./workspace-state.ts";
        \\  const alias = workspace;
        \\  alias.profile.name = "Grace";
        \\</script>
    ;

    var model = try compiler_compile.compile(source, "test/examples/analysis-tracked-root-escape.weiv", allocator);
    defer model.deinit(allocator);

    const report = try cli.formatComponentAnalysisReport(model, allocator);
    defer allocator.free(report);

    try std.testing.expect(std.mem.indexOf(u8, report, "Proxy state graph\n") != null);
    try std.testing.expect(std.mem.indexOf(u8, report, "  tracked roots: 1\n") != null);
    try std.testing.expect(std.mem.indexOf(u8, report, "  root kinds: imported=1 props=0 local=0\n") != null);
    try std.testing.expect(std.mem.indexOf(u8, report, "    - root id=1 binding=workspace kind=imported-tracked\n") != null);
    try std.testing.expect(std.mem.indexOf(u8, report, "  escape warnings: 1\n") != null);
    try std.testing.expect(std.mem.indexOf(u8, report, "    - warning escape-warning binding=workspace related=alias") != null);
    try std.testing.expect(std.mem.indexOf(u8, report, "reason=tracked-root-alias-escape") != null);
    try std.testing.expect(std.mem.indexOf(u8, report, "      rewrite: mutate through the tracked root directly instead of mutating through a local alias\n") != null);
}

test "component analysis report summarizes mixed tracked roots and escape warnings" {
    const allocator = std.testing.allocator;
    const source =
        \\<template>
        \\  <p>{{ workspace.profile.name }}</p>
        \\  <p>{{ props.session.currentUser.name }}</p>
        \\  <p>{{ localState.flags.ready }}</p>
        \\</template>
        \\
        \\<script lang="ts">
        \\  import { workspace } from "./workspace-state.ts";
        \\  export interface Props {
        \\    session: {
        \\      currentUser: { name: string };
        \\    };
        \\  }
        \\  export let props: Props;
        \\  const localState = { flags: { ready: true } };
        \\  const alias = workspace;
        \\  alias.profile.name = "Grace";
        \\</script>
    ;

    var model = try compiler_compile.compile(source, "test/examples/analysis-mixed-tracked-roots.weiv", allocator);
    defer model.deinit(allocator);

    const report = try cli.formatComponentAnalysisReport(model, allocator);
    defer allocator.free(report);

    try std.testing.expect(std.mem.indexOf(u8, report, "  tracked roots: 3\n") != null);
    try std.testing.expect(std.mem.indexOf(u8, report, "  root kinds: imported=1 props=1 local=1\n") != null);
    try std.testing.expect(std.mem.indexOf(u8, report, "    - root id=1 binding=workspace kind=imported-tracked\n") != null);
    try std.testing.expect(std.mem.indexOf(u8, report, "binding=props kind=prop-tracked") != null);
    try std.testing.expect(std.mem.indexOf(u8, report, "binding=localState kind=local-tracked") != null);
    try std.testing.expect(std.mem.indexOf(u8, report, "  escape warnings: 1\n") != null);
    try std.testing.expect(std.mem.indexOf(u8, report, "reason=tracked-root-alias-escape") != null);
}

test "direct browser module emits mixed tracked root graph" {
    const allocator = std.testing.allocator;
    const source =
        \\<template>
        \\  <p>{{ workspace.profile.name }}</p>
        \\  <p>{{ props.session.currentUser.name }}</p>
        \\  <p>{{ localState.flags.ready }}</p>
        \\</template>
        \\
        \\<script lang="ts">
        \\  import { workspace } from "./workspace-state.ts";
        \\  export interface Props {
        \\    session: {
        \\      currentUser: { name: string };
        \\    };
        \\  }
        \\  export let props: Props;
        \\  const localState = { flags: { ready: true } };
        \\  localState.flags.ready = false;
        \\</script>
    ;

    var model = try compiler_compile.compile(source, "test/examples/direct-browser-mixed-tracked-roots.weiv", allocator);
    defer model.deinit(allocator);

    const js = try emitComponentJs(&model, allocator);
    defer allocator.free(js);

    try std.testing.expect(std.mem.indexOf(u8, js, "const workspace = __weiv_getTrackedRoot(\"workspace\", __weiv_import_workspace);") != null);
    try std.testing.expect(std.mem.indexOf(u8, js, "props = __weiv_getTrackedRoot(\"props\", props);") != null);
    try std.testing.expect(std.mem.indexOf(u8, js, "localState = __weiv_getTrackedRoot(\"localState\", localState);") != null);
    try std.testing.expect(std.mem.indexOf(u8, js, "bindingName: \"workspace\", kind: \"imported-tracked\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, js, "bindingName: \"props\", kind: \"prop-tracked\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, js, "bindingName: \"localState\", kind: \"local-tracked\"") != null);
}

fn readFixture(allocator: std.mem.Allocator, path: []const u8) ![]u8 {
    return try std.Io.Dir.cwd().readFileAlloc(std.Io.Threaded.global_single_threaded.io(), path, allocator, .limited(1024 * 1024));
}

test "Panel.weiv lowers to a single default slot outlet" {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const source = try readFixture(allocator, "test/examples/slots/Panel.weiv");
    defer allocator.free(source);
    var model = try compiler_compile.compile(source, "test/examples/slots/Panel.weiv", allocator);
    defer model.deinit(allocator);

    // Top-level: <section><slot><p>...</p></slot></section>
    try std.testing.expectEqual(@as(usize, 1), model.lir_document.nodes.len);
    switch (model.lir_document.nodes[0]) {
        .element => |section| {
            try std.testing.expect(std.mem.eql(u8, section.tag_name, "section"));
            try std.testing.expectEqual(@as(usize, 1), section.children.len);
            switch (section.children[0]) {
                .slot_outlet => |so| {
                    try std.testing.expect(so.name == null);
                    // Panel.weiv fallback: <p class="panel__fallback">...</p>
                    try std.testing.expectEqual(@as(usize, 1), so.fallback_children.len);
                },
                else => return error.UnexpectedIrShape,
            }
        },
        else => return error.UnexpectedIrShape,
    }
}

test "Card.weiv lowers to header named slot and default slot with fallbacks" {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const source = try readFixture(allocator, "test/examples/slots/Card.weiv");
    defer allocator.free(source);
    var model = try compiler_compile.compile(source, "test/examples/slots/Card.weiv", allocator);
    defer model.deinit(allocator);

    // Top-level: <section><header><slot name="header">...</slot></header><div><slot>...</slot></div></section>
    try std.testing.expectEqual(@as(usize, 1), model.lir_document.nodes.len);
    switch (model.lir_document.nodes[0]) {
        .element => |root| {
            try std.testing.expect(std.mem.eql(u8, root.tag_name, "section"));
            try std.testing.expectEqual(@as(usize, 2), root.children.len);

            switch (root.children[0]) {
                .element => |header| {
                    try std.testing.expect(std.mem.eql(u8, header.tag_name, "header"));
                    try std.testing.expectEqual(@as(usize, 1), header.children.len);
                    switch (header.children[0]) {
                        .slot_outlet => |named_outlet| {
                            try std.testing.expect(std.mem.eql(u8, named_outlet.name.?, "header"));
                            // Fallback: <h2 class="card__fallback-title">Untitled</h2>
                            try std.testing.expectEqual(@as(usize, 1), named_outlet.fallback_children.len);
                        },
                        else => return error.UnexpectedIrShape,
                    }
                },
                else => return error.UnexpectedIrShape,
            }

            switch (root.children[1]) {
                .element => |body| {
                    try std.testing.expect(std.mem.eql(u8, body.tag_name, "div"));
                    try std.testing.expectEqual(@as(usize, 1), body.children.len);
                    switch (body.children[0]) {
                        .slot_outlet => |default_outlet| {
                            try std.testing.expect(default_outlet.name == null);
                            // Fallback: <p class="card__fallback-body">No body content.</p>
                            try std.testing.expectEqual(@as(usize, 1), default_outlet.fallback_children.len);
                        },
                        else => return error.UnexpectedIrShape,
                    }
                },
                else => return error.UnexpectedIrShape,
            }
        },
        else => return error.UnexpectedIrShape,
    }
}

test "slot:name directive carries a non-empty source span" {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Construct a hand-built attribute slice that represents `slot:header` at offset 42.
    const input_attrs = [_]ast.Attribute{
        .{
            .name = "slot:header",
            .value = null,
            .span = .{ .start = 42, .end = 53 },
        },
    };

    const result = try directives.split(&input_attrs, allocator);
    defer allocator.free(result.attributes);
    defer allocator.free(result.directives);

    try std.testing.expectEqual(@as(usize, 0), result.attributes.len);
    try std.testing.expectEqual(@as(usize, 1), result.directives.len);

    const slot_dir = result.directives[0].slot_assign;
    try std.testing.expectEqualStrings("header", slot_dir.slot_name);
    try std.testing.expectEqual(@as(usize, 42), slot_dir.span.start);
    try std.testing.expectEqual(@as(usize, 53), slot_dir.span.end);
    try std.testing.expect(slot_dir.span.end > slot_dir.span.start);
}

test "canonical symbol directives and deprecated long forms normalize identically" {
    const allocator = std.testing.allocator;
    const input_attrs = [_]ast.Attribute{
        .{ .name = ":class", .value = "buttonClass", .span = .{ .start = 0, .end = 20 } },
        .{ .name = "bind:disabled", .value = "busy", .span = .{ .start = 21, .end = 41 } },
        .{ .name = "@click", .value = "submit", .span = .{ .start = 42, .end = 57 } },
        .{ .name = "on:focus", .value = "focus", .span = .{ .start = 58, .end = 74 } },
    };

    const result = try directives.split(&input_attrs, allocator);
    defer allocator.free(result.attributes);
    defer allocator.free(result.directives);

    try std.testing.expectEqual(@as(usize, 0), result.attributes.len);
    try std.testing.expectEqual(@as(usize, 4), result.directives.len);
    try std.testing.expectEqualStrings("class", result.directives[0].bind.target_name);
    try std.testing.expectEqualStrings("buttonClass", result.directives[0].bind.expression);
    try std.testing.expectEqualStrings("disabled", result.directives[1].bind.target_name);
    try std.testing.expectEqualStrings("click", result.directives[2].event.event_name);
    try std.testing.expectEqualStrings("submit", result.directives[2].event.expression);
    try std.testing.expectEqualStrings("focus", result.directives[3].event.event_name);
}

test "deprecated bind and event spellings emit warnings while symbols stay clean" {
    const allocator = std.testing.allocator;
    const source =
        \\<template>
        \\  <button bind:disabled="busy" on:click="submit">Legacy</button>
        \\  <button :disabled="busy" @click="submit">Canonical</button>
        \\</template>
        \\<script lang="ts">
        \\  let busy = false;
        \\  function submit() { busy = true; }
        \\</script>
    ;

    var model = try compiler_compile.compile(source, "test/examples/deprecated-directives.weiv", allocator);
    defer model.deinit(allocator);

    try std.testing.expectEqual(@as(usize, 2), model.template_bindings.diagnostics.len);
    for (model.template_bindings.diagnostics) |diagnostic| {
        try std.testing.expectEqualStrings("warning", diagnostic.severity);
        try std.testing.expectEqualStrings("directive.deprecated_syntax", diagnostic.kind);
        try std.testing.expect(diagnostic.span.end > diagnostic.span.start);
    }
}

test "Vue structural attribute spellings emit migration warnings" {
    const allocator = std.testing.allocator;
    const source =
        \\<template>
        \\  <p v-if="ready">Ready</p>
        \\  <p v-for="entry in entries">Entry</p>
        \\</template>
        \\<script lang="ts">
        \\  let ready = true;
        \\  let entries = [1, 2];
        \\</script>
    ;

    var report = try compiler_compile.compileReport(source, "test/examples/vue-structural-warning.weiv", allocator);
    defer report.deinit(allocator);

    var vue_warning_count: usize = 0;
    var saw_if_warning = false;
    var saw_for_warning = false;
    for (report.diagnostics) |diagnostic| {
        if (!std.mem.eql(u8, diagnostic.code, "directive.vue_structural_syntax")) continue;
        vue_warning_count += 1;
        try std.testing.expectEqual(.warning, diagnostic.severity);
        saw_if_warning = saw_if_warning or std.mem.indexOf(u8, diagnostic.message, "use #if") != null;
        saw_for_warning = saw_for_warning or std.mem.indexOf(u8, diagnostic.message, "use #for") != null;
    }
    try std.testing.expectEqual(@as(usize, 2), vue_warning_count);
    try std.testing.expect(saw_if_warning);
    try std.testing.expect(saw_for_warning);
}

test "structural shorthand does not consume ordinary HTML for attributes" {
    const allocator = std.testing.allocator;
    const input_attrs = [_]ast.Attribute{
        .{ .name = "for", .value = "email", .span = .{ .start = 0, .end = 11 } },
        .{ .name = "if", .value = "feature", .span = .{ .start = 12, .end = 24 } },
        .{ .name = "else", .value = null, .span = .{ .start = 25, .end = 29 } },
        .{ .name = "#for", .value = "item in items", .span = .{ .start = 30, .end = 51 } },
        .{ .name = "#if", .value = "item.visible", .span = .{ .start = 52, .end = 70 } },
        .{ .name = "#else", .value = null, .span = .{ .start = 71, .end = 76 } },
    };

    const result = try directives.split(&input_attrs, allocator);
    defer allocator.free(result.attributes);
    defer allocator.free(result.directives);

    try std.testing.expectEqual(@as(usize, 3), result.attributes.len);
    try std.testing.expectEqualStrings("for", result.attributes[0].name);
    try std.testing.expectEqualStrings("email", result.attributes[0].value.?);
    try std.testing.expectEqualStrings("if", result.attributes[1].name);
    try std.testing.expectEqualStrings("feature", result.attributes[1].value.?);
    try std.testing.expectEqualStrings("else", result.attributes[2].name);
    try std.testing.expect(result.attributes[2].value == null);
    try std.testing.expectEqual(@as(usize, 3), result.directives.len);
    try std.testing.expectEqualStrings("item", result.directives[0].for_expr.item_name);
    try std.testing.expectEqualStrings("items", result.directives[0].for_expr.iterable_expr);
    try std.testing.expectEqualStrings("item.visible", result.directives[1].if_expr.expression);
    _ = result.directives[2].else_branch;
}

test "EmptyState.weiv lowers with named message slot and default slot, both with fallbacks" {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const source = try readFixture(allocator, "test/examples/slots/EmptyState.weiv");
    defer allocator.free(source);
    var model = try compiler_compile.compile(source, "test/examples/slots/EmptyState.weiv", allocator);
    defer model.deinit(allocator);

    try std.testing.expectEqual(@as(usize, 1), model.lir_document.nodes.len);
    switch (model.lir_document.nodes[0]) {
        .element => |root| {
            try std.testing.expect(std.mem.eql(u8, root.tag_name, "section"));
            try std.testing.expectEqual(@as(usize, 2), root.children.len);

            switch (root.children[0]) {
                .element => |header| {
                    try std.testing.expect(std.mem.eql(u8, header.tag_name, "header"));
                    try std.testing.expectEqual(@as(usize, 1), header.children.len);
                    switch (header.children[0]) {
                        .slot_outlet => |out| {
                            try std.testing.expect(out.name != null);
                            try std.testing.expect(std.mem.eql(u8, out.name.?, "message"));
                            try std.testing.expectEqual(@as(usize, 1), out.fallback_children.len);
                        },
                        else => return error.UnexpectedIrShape,
                    }
                },
                else => return error.UnexpectedIrShape,
            }

            switch (root.children[1]) {
                .element => |body| {
                    try std.testing.expect(std.mem.eql(u8, body.tag_name, "div"));
                    try std.testing.expectEqual(@as(usize, 1), body.children.len);
                    switch (body.children[0]) {
                        .slot_outlet => |out| {
                            try std.testing.expect(out.name == null);
                            try std.testing.expectEqual(@as(usize, 1), out.fallback_children.len);
                        },
                        else => return error.UnexpectedIrShape,
                    }
                },
                else => return error.UnexpectedIrShape,
            }
        },
        else => return error.UnexpectedIrShape,
    }
}

test "duplicate <slot name> in a component emits slot.duplicate_outlet" {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const source =
        \\<template>
        \\  <section>
        \\    <slot name="header"/>
        \\    <slot name="header"/>
        \\  </section>
        \\</template>
        \\<script lang="ts">
        \\  export interface Props {}
        \\  export let props: Props;
        \\</script>
        \\<style></style>
    ;
    var model = try compiler_compile.compile(source, "test:duplicate_outlet.weiv", allocator);
    defer model.deinit(allocator);

    var found = false;
    for (model.template_bindings.diagnostics) |d| {
        if (std.mem.eql(u8, d.kind, "slot.duplicate_outlet")) found = true;
    }
    try std.testing.expect(found);
}

test "duplicate bare slot:name without template grouping emits slot.duplicate_provision" {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const source =
        \\<template>
        \\  <Card>
        \\    <h2 slot:header>A</h2>
        \\    <h2 slot:header>B</h2>
        \\  </Card>
        \\</template>
        \\<script lang="ts">
        \\  import Card from "./Card.weiv";
        \\  export interface Props {}
        \\  export let props: Props;
        \\</script>
        \\<style></style>
    ;
    var model = try compiler_compile.compile(source, "test:duplicate_provision.weiv", allocator);
    defer model.deinit(allocator);

    var found = false;
    for (model.template_bindings.diagnostics) |d| {
        if (std.mem.eql(u8, d.kind, "slot.duplicate_provision")) found = true;
    }
    try std.testing.expect(found);
}

test "slot:foo with no matching child outlet emits slot.unknown_name" {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Card has slots "header" and default. Use "title" which is unknown.
    const source =
        \\<template>
        \\  <Card>
        \\    <h2 slot:title>oops</h2>
        \\  </Card>
        \\</template>
        \\<script lang="ts">
        \\  import Card from "./Card.weiv";
        \\  export interface Props {}
        \\  export let props: Props;
        \\</script>
        \\<style></style>
    ;
    var model = try compiler_compile.compile(source, "test/examples/slots/CardUsageInvalid.weiv", allocator);
    defer model.deinit(allocator);

    var found = false;
    for (model.template_bindings.diagnostics) |d| {
        if (std.mem.eql(u8, d.kind, "slot.unknown_name")) found = true;
    }
    try std.testing.expect(found);
}

test "providing default content to a child without default slot emits slot.default_not_supported" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const child_source =
        \\<template>
        \\  <header><slot name="title"/></header>
        \\</template>
        \\<script lang="ts">
        \\  export interface Props {}
        \\  export let props: Props;
        \\</script>
        \\<style></style>
    ;
    try tmp.dir.writeFile(std.Io.Threaded.global_single_threaded.io(), .{ .sub_path = "OnlyNamed.weiv", .data = child_source });

    const parent_source =
        \\<template>
        \\  <OnlyNamed>plain text</OnlyNamed>
        \\</template>
        \\<script lang="ts">
        \\  import OnlyNamed from "./OnlyNamed.weiv";
        \\  export interface Props {}
        \\  export let props: Props;
        \\</script>
        \\<style></style>
    ;
    try tmp.dir.writeFile(std.Io.Threaded.global_single_threaded.io(), .{ .sub_path = "Parent.weiv", .data = parent_source });

    // Build absolute path to the parent file so the binder can resolve "./OnlyNamed.weiv"
    const tmp_dir_path = try tmp.dir.realPathFileAlloc(std.Io.Threaded.global_single_threaded.io(), ".", allocator);
    defer allocator.free(tmp_dir_path);
    const parent_path = try std.fs.path.join(allocator, &.{ tmp_dir_path, "Parent.weiv" });
    defer allocator.free(parent_path);

    var model = try compiler_compile.compile(parent_source, parent_path, allocator);
    defer model.deinit(allocator);

    var found = false;
    for (model.template_bindings.diagnostics) |d| {
        if (std.mem.eql(u8, d.kind, "slot.default_not_supported")) found = true;
    }
    try std.testing.expect(found);
}

test "browser render_tree formatter exposes inspectable direct DOM render_tree" {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    const source = try readFixture(allocator, "test/examples/slots/CardUsage.weiv");
    defer allocator.free(source);
    var model = try compiler_compile.compile(source, "test/examples/slots/CardUsage.weiv", allocator);
    defer model.deinit(allocator);
    var render_tree = try browser_render_tree.lower(&model.lir_document, allocator);
    defer render_tree.deinit(allocator);
    const formatted = try browser_render_tree.debug.formatDocument(&render_tree, allocator);
    defer allocator.free(formatted);
    try std.testing.expect(std.mem.indexOf(u8, formatted, "render-tree next_ref_id=") != null);
    try std.testing.expect(std.mem.indexOf(u8, formatted, "component refs=[") != null);
    try std.testing.expect(std.mem.indexOf(u8, formatted, "slot-provision name=header") != null);
    try std.testing.expect(std.mem.indexOf(u8, formatted, "slot-provision name=default") != null);
}
test "conditional direct browser modules destroy outgoing branch before replacement" {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    const source = try readFixture(allocator, "test/examples/basic/conditional-toggle.weiv");
    defer allocator.free(source);
    var model = try compiler_compile.compile(source, "test/examples/basic/conditional-toggle.weiv", allocator);
    defer model.deinit(allocator);
    const js = try emitComponentJs(&model, allocator);
    defer allocator.free(js);
    try std.testing.expect(std.mem.indexOf(u8, js, "function destroyConditionalBranch_") != null);
    try std.testing.expect(std.mem.indexOf(u8, js, "const previous = refs[") != null);
    try std.testing.expect(std.mem.indexOf(u8, js, "destroyConditionalBranch_") != null);
    try std.testing.expect(std.mem.indexOf(u8, js, "replaceBetween(refs[") != null);
}
test "dangling else without sibling if is rejected duplicate coverage" {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    const source =
        \\<template>
        \\  <div #else>Wrong place</div>
        \\</template>
        \\
        \\<script lang="ts">
        \\  export interface Props {}
        \\  export let props: Props;
        \\</script>
    ;
    try std.testing.expectError(
        error.UnexpectedElse,
        compiler_compile.compile(source, "inline-unexpected-else.weiv", allocator),
    );
}
test "direct browser modules emit specialized bound attribute patch code duplicate coverage" {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    const counter_source = try readFixture(allocator, "test/examples/basic/basic-counter.weiv");
    defer allocator.free(counter_source);
    var counter_model = try compiler_compile.compile(counter_source, "test/examples/basic/basic-counter.weiv", allocator);
    defer counter_model.deinit(allocator);
    const counter_js = try emitComponentJs(&counter_model, allocator);
    defer allocator.free(counter_js);
    try std.testing.expect(std.mem.indexOf(u8, counter_js, "applyBoundAttribute(") == null);
    try std.testing.expect(std.mem.indexOf(u8, counter_js, "const __next_") != null);
    try std.testing.expect(std.mem.indexOf(u8, counter_js, "_disabled = Boolean(__value_") != null);
    try std.testing.expect(std.mem.indexOf(u8, counter_js, ".disabled !== __next_") != null);
    try std.testing.expect(std.mem.indexOf(u8, counter_js, ".hasAttribute(\"disabled\")") != null);
    try std.testing.expect(std.mem.indexOf(u8, counter_js, ".disabled = __next_") != null);
    try std.testing.expect(std.mem.indexOf(u8, counter_js, ".setAttribute(\"disabled\", \"\")") != null);
    const todo_item_source = try readFixture(allocator, "test/examples/todomvc/TodoItem.weiv");
    defer allocator.free(todo_item_source);
    var todo_item_model = try compiler_compile.compile(todo_item_source, "test/examples/todomvc/TodoItem.weiv", allocator);
    defer todo_item_model.deinit(allocator);
    const todo_item_js = try emitComponentJs(&todo_item_model, allocator);
    defer allocator.free(todo_item_js);
    try std.testing.expect(std.mem.indexOf(u8, todo_item_js, "applyBoundAttribute(") == null);
    try std.testing.expect(std.mem.indexOf(u8, todo_item_js, "getAttribute(\"class\") !== __next_attr_0_class") == null);
    try std.testing.expect(std.mem.indexOf(u8, todo_item_js, "hasAttribute(\"checked\")") != null);
    try std.testing.expect(std.mem.indexOf(u8, todo_item_js, ".checked = __next_") != null);
    try std.testing.expect(std.mem.indexOf(u8, todo_item_js, ".setAttribute(\"checked\", \"\")") != null);
    const text_input_source = try readFixture(allocator, "test/examples/todomvc/TodoTextInput.weiv");
    defer allocator.free(text_input_source);
    var text_input_model = try compiler_compile.compile(text_input_source, "test/examples/todomvc/TodoTextInput.weiv", allocator);
    defer text_input_model.deinit(allocator);
    const text_input_js = try emitComponentJs(&text_input_model, allocator);
    defer allocator.free(text_input_js);
    try std.testing.expect(std.mem.indexOf(u8, text_input_js, "const __next_0_value = __value_0_value ?? \"\";") != null);
    try std.testing.expect(std.mem.indexOf(u8, text_input_js, "const __next_string_0_value = String(__next_0_value);") != null);
    try std.testing.expect(std.mem.indexOf(u8, text_input_js, ".value !== __next_string_0_value") != null);
    try std.testing.expect(std.mem.indexOf(u8, text_input_js, "getAttribute(\"value\") !== __next_string_0_value") == null);
    try std.testing.expect(std.mem.indexOf(u8, text_input_js, ".setAttribute(\"value\", __next_string_0_value);") != null);
}
test "direct browser modules specialize child component update paths duplicate coverage" {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    const static_source =
        \\<template>
        \\  <Shell></Shell>
        \\</template>
        \\
        \\<script lang="ts">
        \\  import Shell from "./Shell.weiv";
        \\  export interface Props {}
        \\  export let props: Props;
        \\</script>
    ;
    var static_model = try compiler_compile.compile(static_source, "inline-static-child.weiv", allocator);
    defer static_model.deinit(allocator);
    const static_js = try emitComponentJs(&static_model, allocator);
    defer allocator.free(static_js);
    try std.testing.expect(std.mem.indexOf(u8, static_js, "Shell.mountIntoBoundary(") != null);
    try std.testing.expect(std.mem.indexOf(u8, static_js, "undefined, undefined, undefined") != null);
    try std.testing.expect(std.mem.indexOf(u8, static_js, "refs[2].setProps(") == null);
    try std.testing.expect(std.mem.indexOf(u8, static_js, "refs[2].setEventHandlers(") == null);
    try std.testing.expect(std.mem.indexOf(u8, static_js, "refs[2].setSlots(") == null);
    try std.testing.expect(std.mem.indexOf(u8, static_js, "refs[2].update();") == null);
    const panel_usage_source = try readFixture(allocator, "test/examples/slots/PanelUsage.weiv");
    defer allocator.free(panel_usage_source);
    var panel_usage_model = try compiler_compile.compile(panel_usage_source, "test/examples/slots/PanelUsage.weiv", allocator);
    defer panel_usage_model.deinit(allocator);
    const panel_usage_js = try emitComponentJs(&panel_usage_model, allocator);
    defer allocator.free(panel_usage_js);
    try std.testing.expect(std.mem.indexOf(u8, panel_usage_js, ".setProps(") == null);
    try std.testing.expect(std.mem.indexOf(u8, panel_usage_js, ".setEventHandlers(") == null);
    try std.testing.expect(std.mem.indexOf(u8, panel_usage_js, "refs[4].setSlots(") != null);
    try std.testing.expect(std.mem.indexOf(u8, panel_usage_js, "refs[4].update();") != null);
    const loop_source =
        \\<template>
        \\  <Shell #for="item in items"></Shell>
        \\</template>
        \\
        \\<script lang="ts">
        \\  import Shell from "./Shell.weiv";
        \\  export interface Props {}
        \\  export let props: Props;
        \\  let items = [1, 2, 3];
        \\</script>
    ;
    var loop_model = try compiler_compile.compile(loop_source, "inline-static-loop-child.weiv", allocator);
    defer loop_model.deinit(allocator);
    const loop_js = try emitComponentJs(&loop_model, allocator);
    defer allocator.free(loop_js);
    try std.testing.expect(std.mem.indexOf(u8, loop_js, "Shell.mountIntoBoundary(start, end, undefined, undefined, undefined);") != null);
    try std.testing.expect(std.mem.indexOf(u8, loop_js, "record.handle.setProps(") == null);
    try std.testing.expect(std.mem.indexOf(u8, loop_js, "record.handle.setEventHandlers(") == null);
    try std.testing.expect(std.mem.indexOf(u8, loop_js, "record.handle.setSlots(") == null);
    try std.testing.expect(std.mem.indexOf(u8, loop_js, "record.handle.update();") == null);
}
test "slot assignment outside component usage is rejected duplicate coverage" {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    const source =
        \\<template>
        \\  <div slot:header>Wrong place</div>
        \\</template>
        \\
        \\<script lang="ts">
        \\  export interface Props {}
        \\  export let props: Props;
        \\</script>
    ;
    try std.testing.expectError(
        error.InvalidSlotPlacement,
        compiler_compile.compile(source, "inline-invalid-slot-placement.weiv", allocator),
    );
}
test "slot outlet directives are rejected duplicate coverage" {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    const source =
        \\<template>
        \\  <slot slot:header></slot>
        \\</template>
        \\
        \\<script lang="ts">
        \\  export interface Props {}
        \\  export let props: Props;
        \\</script>
    ;
    try std.testing.expectError(
        error.InvalidSlotOutlet,
        compiler_compile.compile(source, "inline-invalid-slot-outlet.weiv", allocator),
    );
}
test "template grouping outside component usage is rejected duplicate coverage" {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    const source =
        \\<template>
        \\  <template slot:header>
        \\    <p>Wrong place</p>
        \\  </template>
        \\</template>
        \\
        \\<script lang="ts">
        \\  export interface Props {}
        \\  export let props: Props;
        \\</script>
    ;
    try std.testing.expectError(
        error.InvalidSlotTemplatePlacement,
        compiler_compile.compile(source, "inline-invalid-top-level-template.weiv", allocator),
    );
}
test "template grouping without slot assignment is rejected duplicate coverage" {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    const source =
        \\<template>
        \\  <Card>
        \\    <template>
        \\      <p>Wrong place</p>
        \\    </template>
        \\  </Card>
        \\</template>
        \\
        \\<script lang="ts">
        \\  import Card from "./Card.weiv";
        \\  export interface Props {}
        \\  export let props: Props;
        \\</script>
    ;
    try std.testing.expectError(
        error.InvalidSlotTemplatePlacement,
        compiler_compile.compile(source, "inline-invalid-slot-template.weiv", allocator),
    );
}

test "experimental state boundary diagnostics own their data and locate template dependencies" {
    const allocator = std.testing.allocator;
    const source =
        \\<template>
        \\  <p>{{ store.count }}</p>
        \\</template>
        \\<script lang="ts">
        \\  import { store } from "third-party";
        \\</script>
    ;
    var model = try compiler_compile.compile(source, "boundary-memory.weiv", allocator);
    defer model.deinit(allocator);
    const entries = try @import("compiler/project/state_dependencies.zig").analyze(&model, allocator);
    defer {
        for (entries) |*entry| entry.deinit(allocator);
        allocator.free(entries);
    }
    try std.testing.expectEqual(@as(usize, 1), entries.len);
    try std.testing.expectEqualStrings("reactivity.unverified_dependency", entries[0].code);
    try std.testing.expectEqualStrings("store.count", source[entries[0].span.?.start..entries[0].span.?.end]);
    try std.testing.expectEqual(@as(u32, 2), entries[0].location.?.line);
    try std.testing.expect(!entries[0].fatal);
}
