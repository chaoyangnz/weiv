#!/usr/bin/env python3
"""Optional live Zig comparison for tracking classification and canonical path inventories."""
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
import { TrackedPaths, TrackedPath } from .compiler.backend.browser.tracked_paths;
import { TrackedRoot, kind_label } from .compiler.backend.browser.tracked_roots;
import { kind_by_name } from .compiler.backend.browser.classify_tracked_roots;
import { collect } from .compiler.backend.browser.collect_tracked_paths;
'''
FALLBACK = 'props.user.name + imported.value + root.child.value + other.child + root.child.value'


def main():
    started = time.monotonic()
    paths = run(['git', 'ls-files', '*.weiv']).stdout.splitlines()
    cases = [(path, (ROOT / path).read_bytes()) for path in paths]
    script = "import { source as imported } from './store'; export interface Props {} export let props: Props; export const root = { child: { value: 1 } }; export let other = { child: 2 };"
    edges = [
        ('{{root . child . value + root.child + other.child}}', script),
        ('{{root + other}}', script),
        ('{{root.child.run() + root.method() + imported.api()}}', script),
        ('{{root[other.child].field + root.x?.value + root?.child}}', script),
        ('{{[...root.list]}}', script),
        ('<p #for="root in other.children">{{root.child}}</p>{{root.child}}', script),
        ('<p #for="root in other.children"><i #for="root in root.children">{{root.child}}</i></p>', script),
        ('{{"root.quoted" + root.value}}', script),
        ('<p bind:title="root.value /*root.fake*/"/>', script),
        ('{{root.child}}', script.replace('export const root', 'export let root') + 'root = {child: {value: 2}};'),
        ('{{root.child + alias.child}}', script + 'export const alias = root;'),
        ('{{root.child + props.user + imported.value}}', script.replace('export const root = { child: { value: 1 } };', 'export function root() {}')),
        ('<Card bind:title="props.user.name" @pick="imported.value"/>', script + 'export const Card = {};'),
        ('{{root.child + root.child.value + root.child}}', script),
        ('<slot>{{props.user.name}}</slot><p #if="other.child">{{root.child}}</p>', script),
        ('hello 🌱', script),
    ]
    cases += [(f'tracked-edge-{i}', ('<template>' + template + '</template><script lang="ts">' + source + '</script>').encode()) for i, (template, source) in enumerate(edges)]
    zig = [ZIG_HEADER, r'''
const lower = @import("src/compiler/lower/lower.zig");
const unit = @import("src/compiler/component_unit.zig");
const roots = @import("src/compiler/backend/browser/tracked_roots.zig");
const paths = @import("src/compiler/backend/browser/tracked_paths.zig");
const Query = struct { start: usize, end: usize, ids: []usize };
const Kind = struct { name: []const u8, kind: ?[]const u8 };
fn kind(model: *const unit.ComponentUnit, name: []const u8) Kind {
    return .{ .name = name, .kind = if (roots.kindByName(model, name)) |value| value.label() else null };
}
''']
    for i, (label, source) in enumerate(cases):
        zig.append(f'''test "tracked {i}" {{
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
    // Only facts/LIR are read by this reference API; other unit fields are unused.
    var model: unit.ComponentUnit = undefined;
    model.script = decoded.facts;
    model.lir_document = try lower.lower(&normalized, &bound, allocator);
    var kinds = std.ArrayList(Kind).empty;
    for (decoded.facts.bindings) |binding| try kinds.append(allocator, kind(&model, binding.name));
    for (decoded.facts.imports) |record| try kinds.append(allocator, kind(&model, record.local_name));
    for ([_][]const u8{{ "missing", "", "props" }}) |name| try kinds.append(allocator, kind(&model, name));
    var table = paths.Table.init(&model, allocator);
    var queries = std.ArrayList(Query).empty;
    for (model.lir_document.expressions) |expression| {{
        var ids = std.ArrayList(usize).empty;
        try table.collectExpressionIds(expression.source, &ids);
        const start = @intFromPtr(expression.source.ptr) - @intFromPtr(sfc.template.content.ptr);
        try queries.append(allocator, .{{ .start = start, .end = start + expression.source.len, .ids = try ids.toOwnedSlice(allocator) }});
    }}
    const fallback = {literal(FALLBACK.encode())};
    var ids = std.ArrayList(usize).empty;
    try table.collectExpressionIds(fallback, &ids);
    try queries.append(allocator, .{{ .start = sfc.template.content.len + 1, .end = sfc.template.content.len + 1 + fallback.len, .ids = try ids.toOwnedSlice(allocator) }});
    const encoded = try std.json.Stringify.valueAlloc(allocator, .{{ .kinds = kinds.items, .queries = queries.items, .roots = table.roots.items, .paths = table.paths.items }}, .{{}});
    std.debug.print("\\nTRACKED {i} {{s}}\\n", .{{encoded}});
}}''')
    fd, name = tempfile.mkstemp(prefix='.cyna-tracked-oracle-', suffix='.zig', dir=ROOT)
    os.close(fd)
    try:
        Path(name).write_text('\n'.join(zig))
        oracle = run([os.environ.get('ZIG', 'zig'), 'test', name, '-L', str(ROOT / 'libs/parser-backend/target/release'), '-lweiv_parser_backend', '-liconv', '-lc'])
    finally:
        Path(name).unlink(missing_ok=True)
    outcomes = {int(i): json.loads(record) for i, record in re.findall(r'TRACKED (\d+) ([^\n]+)', oracle.stderr)}
    assert len(outcomes) == len(cases), 'Incomplete tracking oracle'
    case_sources = []
    for i, (label, source) in enumerate(cases):
        result = outcomes[i]
        cy = []
        for j, entry in enumerate(result['roots']):
            cy.append(f'''fn root_{i}_{j}(table: &const TrackedPaths): void {{
    const root = &table.roots[{j}];
    assert(root.id == {entry['id']}); assert(root.binding_name == {cyna_literal(entry['binding_name'].encode())});
    assert(kind_label(root.kind) == {cyna_literal(entry['kind'].encode())});
}}''')
        for j, entry in enumerate(result['paths']):
            cy.append(f'''fn path_{i}_{j}(table: &const TrackedPaths): void {{
    const path = &table.paths[{j}];
    assert(path.id == {entry['id']}); assert(path.root_id == {entry['root_id']});
    assert(path.path == {cyna_literal(entry['path'].encode())});''')
            if entry['parent_path_id'] is None:
                cy.append('    if path.parent_path_id is id { assert(false); }')
            else:
                cy.append(f'    if path.parent_path_id is id {{ assert(id == {entry["parent_path_id"]}); }} else {{ assert(false); }}')
            cy.append('}')
        cy.append(f'''test {cyna_literal(('tracked corpus: ' + label).encode())} {{
    const catalogs: ComponentManifests = {{ entries: list<ComponentSlotManifest>() }};
    const source = {cyna_literal(source)};
    var report = compile_report(source, {cyna_literal(label.encode())}, &catalogs);
    const unit = take_unit(&report) catch (code) {{ panic("Expected complete unit"); }};
    const bytes = unit.source.bytes();
    const template = string.from(bytes[unit.sfc_document.template.content_span.start..unit.sfc_document.template.content_span.end]);
    const fallback = {cyna_literal(FALLBACK.encode())};
    const combined = $"{{template}} {{fallback}}";
    var table: TrackedPaths = {{ roots: list<TrackedRoot>(), paths: list<TrackedPath>() }};''')
        for entry in result['kinds']:
            query = f'kind_by_name(&unit.script.facts, {cyna_literal(entry["name"].encode())})'
            if entry['kind'] is None:
                cy.append(f'    if {query} is kind {{ assert(false); }}')
            else:
                cy.append(f'    if {query} is kind {{ assert(kind_label(kind) == {cyna_literal(entry["kind"].encode())}); }} else {{ assert(false); }}')
        for j, query in enumerate(result['queries']):
            cy.append(f'    var ids_{j} = list<usize>();')
            cy.append(f'    collect(combined.bytes(), {{ start: {query["start"]}, end: {query["end"]} }}, &unit.script.facts, &unit.lir_document, &table, &ids_{j});')
            cy.append(f'    assert(ids_{j}.len() == {len(query["ids"])});')
            for k, path_id in enumerate(query['ids']):
                cy.append(f'    assert(ids_{j}[{k}] == {path_id});')
        cy.append(f'    assert(table.roots.len() == {len(result["roots"])}); assert(table.paths.len() == {len(result["paths"])});')
        for j in range(len(result['roots'])):
            cy.append(f'    root_{i}_{j}(&table);')
        for j in range(len(result['paths'])):
            cy.append(f'    path_{i}_{j}(&table);')
        cy.append('}')
        case_sources.append('\n'.join(cy))
    temporary = []
    try:
        for start in range(0, len(cases), 8):
            fd, name = tempfile.mkstemp(prefix=f'tracked_corpus_{start:03d}_', suffix='.test.cy', dir=ROOT / 'cyna-port/src')
            os.close(fd)
            temporary.append(Path(name))
            Path(name).write_text(HEADER + '\n'.join(case_sources[start:start + 8]))
        run([os.environ.get('CYNA', 'cyna'), 'test', str(ROOT / 'cyna-port'), '--jobs', '4'])
    finally:
        for path in temporary:
            path.unlink(missing_ok=True)
    print(f'Tracked-root/path parity passed: {len(paths)} components + {len(edges)} targeted inputs; classifications, per-expression leaf IDs, root/path IDs, canonical prefixes and parent links checked ({time.monotonic() - started:.1f}s).')


if __name__ == '__main__':
    main()
