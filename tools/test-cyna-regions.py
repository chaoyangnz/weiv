#!/usr/bin/env python3
"""Optional live Zig parity for owned browser region plans and shared path inventories."""
import json
import os
from pathlib import Path
import re
import runpy
import tempfile
import time

ROOT = Path(__file__).resolve().parents[1]
helpers = runpy.run_path(str(ROOT / 'tools/test-cyna-binding.py'))
run, literal, cyna_literal, ZIG_HEADER = (helpers[name] for name in ('run', 'literal', 'cyna_literal', 'ZIG_HEADER'))
HEADER = '''
import { compile_report, take_unit } from .compiler.compile;
import { ComponentManifests, ComponentSlotManifest } from .compiler.sema.component_manifests;
import { TrackedPaths } from .compiler.backend.browser.tracked_paths;
import { kind_label } from .compiler.backend.browser.tracked_roots;
import { RegionGraph, RegionKind, region_kind_label } from .compiler.backend.browser.region_graph;
import { build } from .compiler.backend.browser.build_region_graph;
import { RenderDocument } from .compiler.backend.browser.render_tree.tree;
import { lower as render } from .compiler.backend.browser.render_tree.lower;

fn provenance(graph: &const RegionGraph, tree: &const RenderDocument): void {
    var i: usize = 0;
    while i < graph.regions.len() {
        const region = &graph.regions[i];
        assert(region.id == i + 1); assert(region.node_id < tree.nodes.len());
        assert(region.span.start == tree.nodes[region.node_id].span.start);
        assert(region.span.end == tree.nodes[region.node_id].span.end);
        const payload = &tree.nodes[region.node_id].payload;
        switch payload {
            .text(value) => { assert(false); }
            .interpolation(value) => { assert(region.kind == RegionKind.text); assert(region.ref_id == value.ref_id); }
            .element(value) => { assert(region.kind == RegionKind.attribute); assert(region.ref_id == value.ref_id); }
            .conditional(value) => { assert(region.kind == RegionKind.conditional); assert(region.ref_id == value.state_ref_id); }
            .for_loop(value) => { assert(region.kind == RegionKind.loop); assert(region.ref_id == value.state_ref_id); }
            .component(value) => { assert(region.kind == RegionKind.child); assert(region.ref_id == value.handle_ref_id); }
            .slot_outlet(value) => { assert(region.kind == RegionKind.slot); assert(region.ref_id == value.handle_ref_id); }
        }
        i = i + 1;
    }
}
'''


def optional(path, value):
    if value is None:
        return f'    if {path} is actual {{ assert(false); }}'
    return f'    if {path} is actual {{ assert(actual == {cyna_literal(value.encode())}); }} else {{ assert(false); }}'


def main():
    started = time.monotonic()
    paths = run(['git', 'ls-files', '*.weiv']).stdout.splitlines()
    cases = [(path, (ROOT / path).read_bytes()) for path in paths]
    script = "import { imported } from './store'; export interface Props {} export let props: Props; export const a = 1; export const b = 2; export const items = []; export const state = {deep: 1}; export const Card = {}; export function helper(){return a + state.deep + imported();}"
    edges = [
        ('', script), ('hello 🌱<p title="static"/>', script),
        ('<div bind:title="a" @click="imported.value">{{imported.value}}</div>{{a}}', script),
        ('<p bind:title="imported.value">{{imported.user.name}}</p>', script),
        ('{{ imported . value }}{{imported.value + 1}}{{(imported.value)}}', script),
        ('<p #if="imported.ready">{{state.deep}}</p><b #else>{{a}}</b>', script),
        ('<i #for="item in items.list">{{item.name}}<b>{{a}}</b></i>', script),
        ('<Card bind:title="imported.title" @pick="state.handler"><p slot:head>{{state.deep}}</p>{{a}}</Card>', script),
        ('<slot name="head"><p bind:title="imported.deep">{{a}}</p></slot>', script),
        ('<slot/><slot name="x"/>', script),
        ('{{42}}<p bind:title="true"/>', script),
        ('{{helper()}}<Card @pick="imported()"/>', script),
        ('<Card><p slot:head>{{state.deep}}</p>{{a}}</Card>', script),
        ('{{imported.value()}}{{imported.a + imported.b}}', script),
        ('{{"state.fake" + state.deep}}', script),
        ('{{state.deep}}', script.replace('export const state', 'export let state') + 'state = {deep: 2};'),
        ('{{state.deep + alias.deep}}', script + 'export const alias = state;'),
        ('<i #for="helper in items">{{helper()}}</i>', script),
        ('🌱{{imported.value}}{{\vimported.deep\f}}', script),
        ('{{helper() + imported.value}}', script),
    ]
    cases += [(f'region-edge-{i}', ('<template>' + template + '</template><script lang="ts">' + source + '</script>').encode()) for i, (template, source) in enumerate(edges)]
    zig = [ZIG_HEADER, r'''
const lower = @import("src/compiler/lower/lower.zig");
const unit = @import("src/compiler/component_unit.zig");
const render = @import("src/compiler/backend/browser/render_tree/lower.zig");
const regions = @import("src/compiler/backend/browser/region_graph.zig");
const Region = struct {
    id: usize, kind: []const u8, ref_id: usize, name: ?[]const u8,
    dependency_names: []const []const u8, tracked_path_ids: []const usize,
    precise_import_name: ?[]const u8,
};
''']
    for i, (label, source) in enumerate(cases):
        zig.append(f'''test "regions {i}" {{
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator); defer arena.deinit();
    const allocator = arena.allocator();
    const sfc = try parser.parseSfc({literal(source)});
    const raw = try parser.parseTemplate(sfc.template.content, allocator);
    const normalized = try parser.normalizeTemplate(&raw, allocator);
    const payload = try analyze(sfc.script.content, {literal(label.encode())}, allocator);
    const decoded = try decoder.decode(payload, allocator);
    var catalog = Catalog{{ .available = false, .manifest = .{{ .entries = &.{{}} }} }};
    var provider = slots.Provider{{ .context = &catalog, .manifest_for = provide }};
    const bound = try binder.bind(&normalized, &decoded.facts, &provider, allocator);
    // These analyses read only facts/LIR from the reference unit.
    var model: unit.ComponentUnit = undefined;
    model.script = decoded.facts;
    model.lir_document = try lower.lower(&normalized, &bound, allocator);
    const tree = try render.lower(&model.lir_document, allocator);
    const graph = try regions.build(&model, &tree, allocator);
    var records = std.ArrayList(Region).empty;
    for (graph.regions.items) |region| try records.append(allocator, .{{
        .id = region.id, .kind = region.kind, .ref_id = region.ref_id, .name = region.name,
        .dependency_names = region.dependency_names.items, .tracked_path_ids = region.tracked_path_ids.items,
        .precise_import_name = region.precise_import_name,
    }});
    const encoded = try std.json.Stringify.valueAlloc(allocator, .{{ .roots = graph.table.roots.items, .paths = graph.table.paths.items, .regions = records.items }}, .{{}});
    std.debug.print("\\nREGIONS {i} {{s}}\\n", .{{encoded}});
}}''')
    fd, name = tempfile.mkstemp(prefix='.cyna-regions-oracle-', suffix='.zig', dir=ROOT)
    os.close(fd)
    try:
        Path(name).write_text('\n'.join(zig))
        oracle = run([os.environ.get('ZIG', 'zig'), 'test', name, '-L', str(ROOT / 'libs/parser-backend/target/release'), '-lweiv_parser_backend', '-liconv', '-lc'])
    finally:
        Path(name).unlink(missing_ok=True)
    outcomes = {int(i): json.loads(record) for i, record in re.findall(r'REGIONS (\d+) ([^\n]+)', oracle.stderr)}
    assert len(outcomes) == len(cases), 'Incomplete region oracle'
    case_sources = []
    for i, (label, source) in enumerate(cases):
        result = outcomes[i]
        cy = []
        for j, root in enumerate(result['roots']):
            cy.append(f'''fn root_{i}_{j}(graph: &const RegionGraph): void {{
    const root = &graph.table.roots[{j}];
    assert(root.id == {root['id']}); assert(root.binding_name == {cyna_literal(root['binding_name'].encode())});
    assert(kind_label(root.kind) == {cyna_literal(root['kind'].encode())});
}}''')
        for j, path in enumerate(result['paths']):
            cy.append(f'''fn path_{i}_{j}(graph: &const RegionGraph): void {{
    const path = &graph.table.paths[{j}];
    assert(path.id == {path['id']}); assert(path.root_id == {path['root_id']}); assert(path.path == {cyna_literal(path['path'].encode())});''')
            if path['parent_path_id'] is None:
                cy.append('    if path.parent_path_id is id { assert(false); }')
            else:
                cy.append(f'    if path.parent_path_id is id {{ assert(id == {path["parent_path_id"]}); }} else {{ assert(false); }}')
            cy.append('}')
        for j, region in enumerate(result['regions']):
            cy.append(f'''fn region_{i}_{j}(graph: &const RegionGraph): void {{
    const region = &graph.regions[{j}];
    assert(region.id == {region['id']}); assert(region.ref_id == {region['ref_id']});
    assert(region_kind_label(region.kind) == {cyna_literal(region['kind'].encode())});''')
            cy.append(optional('region.name', region['name']))
            cy.append(optional('region.precise_import_name', region['precise_import_name']))
            cy.append(f'    assert(region.dependency_names.len() == {len(region["dependency_names"])});')
            for k, dep in enumerate(region['dependency_names']):
                cy.append(f'    assert(region.dependency_names[{k}] == {cyna_literal(dep.encode())});')
            cy.append(f'    assert(region.tracked_path_ids.len() == {len(region["tracked_path_ids"])});')
            for k, path_id in enumerate(region['tracked_path_ids']):
                cy.append(f'    assert(region.tracked_path_ids[{k}] == {path_id});')
            cy.append('}')
        cy.append(f'''test {cyna_literal(('region corpus: ' + label).encode())} {{
    const catalogs: ComponentManifests = {{ entries: list<ComponentSlotManifest>() }};
    const source = {cyna_literal(source)};
    var report = compile_report(source, {cyna_literal(label.encode())}, &catalogs);
    const unit = take_unit(&report) catch (code) {{ panic("Expected complete unit"); }};
    const bytes = unit.source.bytes();
    const template = bytes[unit.sfc_document.template.content_span.start..unit.sfc_document.template.content_span.end];
    const tree = render(&unit.lir_document);
    const graph = build(template, &unit.script.facts, &unit.lir_document, &tree);
    provenance(&graph, &tree);
    assert(graph.table.roots.len() == {len(result['roots'])}); assert(graph.table.paths.len() == {len(result['paths'])});
    assert(graph.regions.len() == {len(result['regions'])});''')
        for group in ('roots', 'paths', 'regions'):
            prefix = {'roots': 'root', 'paths': 'path', 'regions': 'region'}[group]
            for j in range(len(result[group])):
                cy.append(f'    {prefix}_{i}_{j}(&graph);')
        cy.append('}')
        case_sources.append('\n'.join(cy))
    temporary = []
    try:
        for start in range(0, len(cases), 8):
            fd, name = tempfile.mkstemp(prefix=f'region_corpus_{start:03d}_', suffix='.test.cy', dir=ROOT / 'cyna-port/src')
            os.close(fd)
            temporary.append(Path(name))
            Path(name).write_text(HEADER + '\n'.join(case_sources[start:start + 8]))
        run([os.environ.get('CYNA', 'cyna'), 'test', str(ROOT / 'cyna-port'), '--jobs', '4'])
    finally:
        for path in temporary:
            path.unlink(missing_ok=True)
    print(f'Region-graph parity passed: {len(paths)} components + {len(edges)} targeted inputs; regions, refs, names, dependencies, shared root/path inventory, import hints and added provenance checked ({time.monotonic() - started:.1f}s).')


if __name__ == '__main__':
    main()
