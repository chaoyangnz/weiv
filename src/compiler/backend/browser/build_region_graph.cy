// Operation: valid render tree + immutable template/facts -> owned browser update plan.
import { Span } from .compiler.source;
import { ScriptFacts } from .compiler.sema.script_facts;
import { LirDocument } from .compiler.lower.lir;
import { RenderDocument, RenderElement, RenderComponent, RenderConditional, RenderForLoop, RenderSlotOutlet } from .compiler.backend.browser.render_tree.tree;
import { Region, RegionGraph, RegionKind } from .compiler.backend.browser.region_graph;
import { TrackedKind, TrackedRoot } from .compiler.backend.browser.tracked_roots;
import { TrackedPath, TrackedPaths } from .compiler.backend.browser.tracked_paths;
import { collect as collect_paths } from .compiler.backend.browser.collect_tracked_paths;
import { DependencyList } from .compiler.backend.browser.dependencies;
import { collect_expression, collect_node, retain_visible } from .compiler.backend.browser.collect_dependencies;

fn push_children(work: &List<usize>, children: &const List<usize>): void {
    var i = children.len();
    while i > 0 {
        i = i - 1;
        work.push(children[i]);
    }
}
fn span_name(source: []const u8, span: ?Span): ?string {
    if span is range {
        const result: ?string = string.from(source[range.start..range.end]);
        return result;
    }
    return none;
}
fn whitespace(byte: u8): bool {
    return byte == 32 or (byte >= 9 and byte <= 13);
}
fn precise_import(source: []const u8, expression: Span, deps: &const DependencyList, ids: &const List<usize>, table: &const TrackedPaths): ?string {
    if deps.items.len() != 1 or ids.len() != 1 {
        return none;
    }
    const path = &table.paths[ids[0] - 1];
    const root = &table.roots[path.root_id - 1];
    if root.kind != TrackedKind.imported_tracked {
        return none;
    }
    for byte in path.path.bytes() {
        if byte == 32 or byte == 9 or byte == 13 or byte == 10 {
            return none;
        }
    }
    var start = expression.start;
    var end = expression.end;
    while start < end and whitespace(source[start]) {
        start = start + 1;
    }
    while end > start and whitespace(source[end - 1]) {
        end = end - 1;
    }
    if string.from(source[start..end]) != path.path or deps.items[0] != root.binding_name {
        return none;
    }
    const result: ?string = string.from(root.binding_name.bytes());
    return result;
}
fn append_expression(source: []const u8, script: &const ScriptFacts, lir: &const LirDocument, tree: &const RenderDocument, graph: &RegionGraph, node_id: usize, kind: RegionKind, ref_id: usize, name: ?string, expression: Span): void {
    var deps: DependencyList = {
        items: list<string>()
    };
    const locals = list<string>();
    collect_expression(source, expression, script, lir, &locals, &deps, {
        retain_imported_calls: true
    });
    retain_visible(script, &deps);
    var paths = list<usize>();
    collect_paths(source, expression, script, lir, &graph.table, &paths);
    const hint = precise_import(source, expression, &deps, &paths, &graph.table);
    deps.items = list<string>() @ const names;
    graph.regions.push(Region {
        id: graph.regions.len() + 1,
        kind: kind,
        ref_id: ref_id,
        name: name,
        dependency_names: names,
        tracked_path_ids: paths,
        precise_import_name: hint,
        node_id: node_id,
        span: tree.nodes[node_id].span
    });
}
fn create_region(source: []const u8, script: &const ScriptFacts, lir: &const LirDocument, tree: &const RenderDocument, id: usize, node_id: usize, kind: RegionKind, ref_id: usize, name: ?string): Region {
    var deps: DependencyList = {
        items: list<string>()
    };
    const locals = list<string>();
    collect_node(source, script, lir, tree, node_id, &locals, &deps, {
        retain_imported_calls: true
    });
    retain_visible(script, &deps);
    deps.items = list<string>() @ const names;
    return {
        id: id,
        kind: kind,
        ref_id: ref_id,
        name: name,
        dependency_names: names,
        tracked_path_ids: list<usize>(),
        precise_import_name: none,
        node_id: node_id,
        span: tree.nodes[node_id].span
    };
}
fn structural(source: []const u8, script: &const ScriptFacts, lir: &const LirDocument, tree: &const RenderDocument, graph: &RegionGraph, node_id: usize, kind: RegionKind, ref_id: usize, name: ?string, expression: Span): void {
    var region = create_region(source, script, lir, tree, graph.regions.len() + 1, node_id, kind, ref_id, name);
    collect_paths(source, expression, script, lir, &graph.table, &region.tracked_path_ids);
    graph.regions.push(region);
}
fn element(source: []const u8, script: &const ScriptFacts, lir: &const LirDocument, tree: &const RenderDocument, graph: &RegionGraph, node_id: usize, value: &const RenderElement, work: &List<usize>): void {
    var i: usize = 0;
    while i < value.bind_effects.len() {
        const effect = &value.bind_effects[i];
        switch effect {
            .bind(binding) => {
                append_expression(source, script, lir, tree, graph, node_id, RegionKind.attribute, value.ref_id, span_name(source, binding.name), binding.expression);
            }
            .event(event) => {}
        }
        i = i + 1;
    }
    push_children(work, &value.children);
}
fn component(source: []const u8, script: &const ScriptFacts, lir: &const LirDocument, tree: &const RenderDocument, graph: &RegionGraph, node_id: usize, value: &const RenderComponent): void {
    var region = create_region(source, script, lir, tree, graph.regions.len() + 1, node_id, RegionKind.child, value.handle_ref_id, span_name(source, value.tag_name));
    var i: usize = 0;
    while i < value.bind_effects.len() {
        const effect = &value.bind_effects[i];
        switch effect {
            .bind(binding) => {
                collect_paths(source, binding.expression, script, lir, &graph.table, &region.tracked_path_ids);
            }
            .event(event) => {}
        }
        i = i + 1;
    }
    i = 0;
    while i < value.event_effects.len() {
        const effect = &value.event_effects[i];
        switch effect {
            .bind(binding) => {
                collect_paths(source, binding.expression, script, lir, &graph.table, &region.tracked_path_ids);
            }
            .event(event) => {
                collect_paths(source, event.expression, script, lir, &graph.table, &region.tracked_path_ids);
            }
        }
        i = i + 1;
    }
    graph.regions.push(region);
}

pub fn build(source: []const u8, script: &const ScriptFacts, lir: &const LirDocument, tree: &const RenderDocument): RegionGraph {
    var graph: RegionGraph = {
        table: {
            roots: list<TrackedRoot>(),
            paths: list<TrackedPath>()
        },
        regions: list<Region>()
    };
    var work = list<usize>();
    push_children(&work, &tree.roots);
    while work.len() > 0 {
        const id = work.pop();
        const payload = &tree.nodes[id].payload;
        switch payload {
            .text(value) => {}
            .interpolation(value) => {
                append_expression(source, script, lir, tree, &graph, id, RegionKind.text, value.ref_id, none, value.expression);
            }
            .element(value) => {
                element(source, script, lir, tree, &graph, id, &value, &work);
            }
            .component(value) => {
                component(source, script, lir, tree, &graph, id, &value);
            }
            .conditional(value) => {
                structural(source, script, lir, tree, &graph, id, RegionKind.conditional, value.state_ref_id, none, value.condition);
            }
            .for_loop(value) => {
                structural(source, script, lir, tree, &graph, id, RegionKind.loop, value.state_ref_id, span_name(source, value.item_name), value.iterable_expr);
            }
            .slot_outlet(value) => {
                graph.regions.push(create_region(source, script, lir, tree, graph.regions.len() + 1, id, RegionKind.slot, value.handle_ref_id, span_name(source, value.name)));
            }
        }
    }
    return graph;
}
