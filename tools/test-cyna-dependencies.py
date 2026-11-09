#!/usr/bin/env python3
"""Optional live Zig parity for expression/helper/subtree dependency collection."""
import argparse
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
import { DependencyList } from .compiler.backend.browser.dependencies;
import { collect_expression, collect_node, retain_visible } from .compiler.backend.browser.collect_dependencies;
import { lower as render } from .compiler.backend.browser.render_tree.lower;
'''
FALLBACK = "f() + a + props.name + imported() + item + 'b' /*c*/"


def checks(name, expected):
    lines = [f'    assert(output.items.len() == {len(expected)});']
    for i, item in enumerate(expected):
        lines.append(f'    assert(output.items[{i}] == {cyna_literal(item.encode())});')
    return f'fn {name}(output: &const DependencyList): void {{\n' + '\n'.join(lines) + '\n}'


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--targeted-only', action='store_true', help='Run targeted cases without the tracked component corpus.')
    args = parser.parse_args()
    started = time.monotonic()
    paths = [] if args.targeted_only else run(['git', 'ls-files', '*.weiv']).stdout.splitlines()
    cases = [(path, (ROOT / path).read_bytes()) for path in paths]
    script = "import { imported } from './store'; export interface Props {} export let props: Props; export const a = 1; export let b = 2; export const c = 3; export const items = []; export const Card = {}; export function f(){return g()+a;} export function g(){return b;}"
    edges = [
        ('{{f() + a}}', script), ('{{f + a + f()}}', script),
        ('{{imported() + imported.value}}', script),
        ('{{f()}}', script.replace('return b;', 'return f()+b;')),
        ('{{f() + imported()}}', script.replace('return g()+a;', 'return imported()+a;')),
        ('<div @click="imported" bind:title="a"><Card @pick="imported" bind:title="b">{{c}}</Card></div>', script),
        ('<div><i #for="item in items">{{item.name}}</i>{{item}}</div>', script),
        ('<Card><p slot:head>{{a}}</p>{{b}}<i slot:head>{{c}}</i></Card>', script),
        ('<div><p #if="a"><i #for="item in items">{{item.name}}</i></p><p #else><slot>{{b}}</slot></p></div>', script),
        ('{{"a" + b /* c */}}', script),
        ('{{f()}}', script.replace('return g()+a;', 'return Math.random() + a;')),
        ('{{f() + f}}', script.replace('export function f(){return g()+a;}', 'export const f = a;')),
        ('<slot>{{f()}}</slot>', script),
        ('<p #for="a in items">{{a}}<i #for="b in a.children">{{b}}</i></p>', script),
        ('{{missing + a}}', script), ('hello 🌱', script),
        ('<i #for="f in items">{{f()}}</i>', script.replace('return g()+a;', 'return a;')),
    ]
    cases += [(f'dependency-edge-{i}', ('<template>' + template + '</template><script lang="ts">' + source + '</script>').encode()) for i, (template, source) in enumerate(edges)]
    zig = [ZIG_HEADER, r'''
const lower = @import("src/compiler/lower/lower.zig");
const unit = @import("src/compiler/component_unit.zig");
const render = @import("src/compiler/backend/browser/render_tree/lower.zig");
const dependencies = @import("src/compiler/backend/browser/dependencies.zig");
const Query = struct { start: usize, end: usize, before: [][]const u8, after: [][]const u8 };
const Node = struct { before: [][]const u8, after: [][]const u8 };
const Result = struct { expressions: []Query, nodes: []Node };
''']
    for i, (label, source) in enumerate(cases):
        zig.append(f'''test "dependencies {i}" {{
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
    var model: unit.ComponentUnit = undefined;
    model.script = decoded.facts;
    model.lir_document = try lower.lower(&normalized, &bound, allocator);
    const tree = try render.lower(&model.lir_document, allocator);
    var results = std.ArrayList(Result).empty;
    const locals = [_][]const u8{{ "item" }};
    for ([_]bool{{ false, true }}) |retain| {{
        var expressions = std.ArrayList(Query).empty;
        for (model.lir_document.expressions) |expression| {{
            var deps = dependencies.DepList{{ .retain_imported_calls = retain }};
            try dependencies.collectExpressionDeps(&model, expression.source, &locals, &deps, allocator);
            const before = try allocator.dupe([]const u8, deps.items.items);
            dependencies.retainVisibleBindingDeps(&model, &deps);
            const start = @intFromPtr(expression.source.ptr) - @intFromPtr(sfc.template.content.ptr);
            try expressions.append(allocator, .{{ .start = start, .end = start + expression.source.len, .before = before, .after = try allocator.dupe([]const u8, deps.items.items) }});
        }}
        const fallback = {literal(FALLBACK.encode())};
        var deps = dependencies.DepList{{ .retain_imported_calls = retain }};
        try dependencies.collectExpressionDeps(&model, fallback, &locals, &deps, allocator);
        const before = try allocator.dupe([]const u8, deps.items.items);
        dependencies.retainVisibleBindingDeps(&model, &deps);
        try expressions.append(allocator, .{{ .start = sfc.template.content.len + 1, .end = sfc.template.content.len + 1 + fallback.len, .before = before, .after = try allocator.dupe([]const u8, deps.items.items) }});
        var nodes = std.ArrayList(Node).empty;
        for (tree.nodes) |node| {{
            var node_deps = dependencies.DepList{{ .retain_imported_calls = retain }};
            try dependencies.collectNodeDeps(&model, node, &locals, &node_deps, allocator);
            const node_before = try allocator.dupe([]const u8, node_deps.items.items);
            dependencies.retainVisibleBindingDeps(&model, &node_deps);
            try nodes.append(allocator, .{{ .before = node_before, .after = try allocator.dupe([]const u8, node_deps.items.items) }});
        }}
        try results.append(allocator, .{{ .expressions = try expressions.toOwnedSlice(allocator), .nodes = try nodes.toOwnedSlice(allocator) }});
    }}
    const encoded = try std.json.Stringify.valueAlloc(allocator, results.items, .{{}});
    std.debug.print("\\nDEPENDENCIES {i} {{s}}\\n", .{{encoded}});
}}''')
    fd, name = tempfile.mkstemp(prefix='.cyna-dependencies-oracle-', suffix='.zig', dir=ROOT)
    os.close(fd)
    try:
        Path(name).write_text('\n'.join(zig))
        oracle = run([os.environ.get('ZIG', 'zig'), 'test', name, '-L', str(ROOT / 'libs/parser-backend/target/release'), '-lweiv_parser_backend', '-liconv', '-lc'])
    finally:
        Path(name).unlink(missing_ok=True)
    outcomes = {int(i): json.loads(record) for i, record in re.findall(r'DEPENDENCIES (\d+) ([^\n]+)', oracle.stderr)}
    assert len(outcomes) == len(cases), 'Incomplete dependency oracle'
    case_sources = []
    for i, (label, source) in enumerate(cases):
        for policy, result in enumerate(outcomes[i]):
            cy = []
            for group, records in result.items():
                for j, record in enumerate(records):
                    for stage in ('before', 'after'):
                        cy.append(checks(f'expect_{i}_{policy}_{group}_{j}_{stage}', record[stage]))
            cy.append(f'''test {cyna_literal(('dependencies: ' + label + (' retained' if policy else ' omitted')).encode())} {{
    const catalogs: ComponentManifests = {{ entries: list<ComponentSlotManifest>() }};
    const source = {cyna_literal(source)};
    var report = compile_report(source, {cyna_literal(label.encode())}, &catalogs);
    const unit = take_unit(&report) catch (code) {{ panic("Expected complete unit"); }};
    const bytes = unit.source.bytes();
    const template = string.from(bytes[unit.sfc_document.template.content_span.start..unit.sfc_document.template.content_span.end]);
    const fallback = {cyna_literal(FALLBACK.encode())};
    const combined = $"{{template}} {{fallback}}";
    const tree = render(&unit.lir_document);
    var locals = list<string>(); locals.push("item");''')
            for j, record in enumerate(result['expressions']):
                cy.append(f'''    var expression_{j}: DependencyList = {{ items: list<string>() }};
    collect_expression(combined.bytes(), {{ start: {record['start']}, end: {record['end']} }}, &unit.script.facts, &unit.lir_document, &locals, &expression_{j}, {{ retain_imported_calls: {str(bool(policy)).lower()} }});
    expect_{i}_{policy}_expressions_{j}_before(&expression_{j});
    retain_visible(&unit.script.facts, &expression_{j});
    expect_{i}_{policy}_expressions_{j}_after(&expression_{j});''')
            cy.append(f'    assert(tree.roots.len() == {len(result["nodes"])});')
            for j, record in enumerate(result['nodes']):
                cy.append(f'''    var node_{j}: DependencyList = {{ items: list<string>() }};
    collect_node(template.bytes(), &unit.script.facts, &unit.lir_document, &tree, tree.roots[{j}], &locals, &node_{j}, {{ retain_imported_calls: {str(bool(policy)).lower()} }});
    expect_{i}_{policy}_nodes_{j}_before(&node_{j});
    retain_visible(&unit.script.facts, &node_{j});
    expect_{i}_{policy}_nodes_{j}_after(&node_{j});''')
            cy.append('}')
            case_sources.append('\n'.join(cy))
    temporary = []
    try:
        for start in range(0, len(case_sources), 8):
            fd, name = tempfile.mkstemp(prefix=f'dependency_corpus_{start:03d}_', suffix='.test.cy', dir=ROOT / 'cyna-port/src')
            os.close(fd)
            temporary.append(Path(name))
            Path(name).write_text(HEADER + '\n'.join(case_sources[start:start + 8]))
        run([os.environ.get('CYNA', 'cyna'), 'test', str(ROOT / 'cyna-port'), '--jobs', '4'])
    finally:
        for path in temporary:
            path.unlink(missing_ok=True)
    print(f'Dependency parity passed: {len(paths)} components + {len(edges)} targeted inputs, both imported-call policies; expression/helper closure, fallback scanning, root subtree collection and stable visible filtering checked ({time.monotonic() - started:.1f}s).')


if __name__ == '__main__':
    main()
