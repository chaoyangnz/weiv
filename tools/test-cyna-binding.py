#!/usr/bin/env python3
"""Optional full template-binding parity; native Cyna tests remain the default."""
import json
import os
from pathlib import Path
import re
import runpy
import tempfile
import time

ROOT = Path(__file__).resolve().parents[1]
helpers = runpy.run_path(str(ROOT / 'tools/test-cyna-sfc.py'))
run, literal, cyna_literal = (helpers[name] for name in ('run', 'literal', 'cyna_literal'))

ZIG_HEADER = r'''
const std = @import("std");
const parser = @import("src/compiler/parser/index.zig");
const decoder = @import("src/compiler/sema/decode_script_facts.zig");
const binder = @import("src/compiler/sema/bind.zig");
const slots = @import("src/compiler/sema/slot_manifest.zig");
extern fn weiv_script_analyze(source: [*:0]const u8, path: [*:0]const u8) ?[*:0]u8;
extern fn weiv_backend_free(pointer: [*:0]u8) void;
fn analyze(source: []const u8, path: []const u8, allocator: std.mem.Allocator) ![]u8 {
    const source_z = try allocator.dupeSentinel(u8, source, 0); defer allocator.free(source_z);
    const path_z = try allocator.dupeSentinel(u8, path, 0); defer allocator.free(path_z);
    const result = weiv_script_analyze(source_z.ptr, path_z.ptr) orelse return error.BackendFailure;
    defer weiv_backend_free(result);
    return try allocator.dupe(u8, std.mem.span(result));
}
const Catalog = struct { available: bool, manifest: slots.Manifest };
fn provide(context: *anyopaque, tag: []const u8) anyerror!?*const slots.Manifest {
    const catalog: *const Catalog = @ptrCast(@alignCast(context));
    if (catalog.available and std.mem.eql(u8, tag, "Card")) return &catalog.manifest;
    return null;
}
'''


def checks(value, path, output, counter):
    if isinstance(value, dict):
        for key, item in value.items():
            access = path + '.' + key
            if key == 'kind' and path.startswith('result.diagnostics['):
                origin = 'script' if item == 'framework.reserved_binding' else 'template'
                output.append(f'    assert({path}.origin == BindingSource.{origin});')
            if key == 'name' and path.startswith('result.own_slot_manifest.entries['):
                name = f'optional_{counter[0]}'
                counter[0] += 1
                if item is None:
                    output.append(f'    if {access} is {name} {{ assert(false); }}')
                else:
                    output.append(f'    if {access} is {name} {{ assert({name} == {cyna_literal(item.encode())}); }} else {{ assert(false); }}')
            elif key == 'source' and path.startswith('result.expressions['):
                output.append(f'    assert(text(source, {access}) == {cyna_literal(item.encode())});')
            else:
                checks(item, access, output, counter)
    elif isinstance(value, list):
        output.append(f'    assert({path}.len() == {len(value)});')
        for i, item in enumerate(value):
            checks(item, f'{path}[{i}]', output, counter)
    elif isinstance(value, bool):
        output.append(f'    assert({"" if value else "not "}{path});')
    elif isinstance(value, int):
        output.append(f'    assert({path} == {value});')
    elif isinstance(value, str):
        output.append(f'    assert({path} == {cyna_literal(value.encode())});')
    else:
        raise AssertionError(f'Unhandled binding oracle value at {path}: {value!r}')


def groups(expected):
    counter = [0]
    for field, value in expected.items():
        if field == 'own_slot_manifest':
            value = value['entries']
            field += '.entries'
        yield [f'    assert(result.{field}.len() == {len(value)});']
        for i, record in enumerate(value):
            output = []
            checks(record, f'result.{field}[{i}]', output, counter)
            yield output


def main():
    started = time.monotonic()
    paths = run(['git', 'ls-files', '*.weiv']).stdout.splitlines()
    cases = [(path, (ROOT / path).read_bytes(), False) for path in paths]
    script = 'export interface Props {} export let props: Props; export const Card = {}; export const items = []; export const user = {}; export const spread = []; export function helper(){ return Date.now(); }'
    edges = [
        ('{{ missing + missing() }}', False),
        ('{{user.name + ...spread + `hello ${user.name}` + emit(\'x\')}}', False),
        ('<a #for="item in items">{{item}}</a>{{item}}', False),
        ('<Card/><Missing/><custom-element/>', False),
        ('<p v-if="x" v-for="x" on:click="missing" bind:value="other"/>', False),
        ('{{helper() + helper()}}', False), ('{{helper + helper()}}', False),
        ('<Card><p slot:unknown/>text</Card>', True),
        ('<Card><p slot:head/></Card>', True),
        ('<Card><template slot:head/><template slot:head/></Card>', True),
        ('<Card><template slot:head/><p slot:head/><template slot:head/></Card>', True),
        ('<Card><p #if="true" slot:unknown/></Card>', True),
        ('<slot><slot name="hidden"/>{{missing}}</slot><slot/>', False),
    ]
    cases += [(f'binding-edge-{i}', ('<template>' + template + '</template><script lang="ts">' + script + '</script>').encode(), available) for i, (template, available) in enumerate(edges)]
    zig = [ZIG_HEADER]
    for i, (label, source, available) in enumerate(cases):
        zig.append(f'''test "binding {i}" {{
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator); defer arena.deinit();
    const allocator = arena.allocator();
    const sections = try parser.parseSfc({literal(source)});
    const raw = parser.parseTemplate(sections.template.content, allocator) catch |err| {{
        std.debug.print("\\nBIND {i} PARSE {{s}}\\n", .{{@errorName(err)}}); return;
    }};
    const normalized = parser.normalizeTemplate(&raw, allocator) catch |err| {{
        std.debug.print("\\nBIND {i} NORMALIZE {{s}}\\n", .{{@errorName(err)}}); return;
    }};
    const payload = try analyze(sections.script.content, {literal(label.encode())}, allocator);
    const decoded = try decoder.decode(payload, allocator);
    var entries = [_]slots.SlotEntry{{.{{ .name = "head", .span = .{{ .start = 0, .end = 0 }} }}}};
    var catalog = Catalog{{ .available = {str(available).lower()}, .manifest = .{{ .entries = &entries }} }};
    var provider = slots.Provider{{ .context = &catalog, .manifest_for = provide }};
    const result = try binder.bind(&normalized, &decoded.facts, &provider, allocator);
    const encoded = try std.json.Stringify.valueAlloc(allocator, .{{ .payload = payload, .result = result }}, .{{}});
    std.debug.print("\\nBIND {i} OK {{s}}\\n", .{{encoded}});
}}
''')
    fd, oracle_name = tempfile.mkstemp(prefix='.cyna-binding-oracle-', suffix='.zig', dir=ROOT)
    os.close(fd)
    try:
        Path(oracle_name).write_text('\n'.join(zig))
        oracle = run([os.environ.get('ZIG', 'zig'), 'test', oracle_name, '-L', str(ROOT / 'libs/parser-backend/target/release'), '-lweiv_parser_backend', '-liconv', '-lc'])
    finally:
        Path(oracle_name).unlink(missing_ok=True)
    expected = {int(i): value for i, value in re.findall(r'BIND (\d+) ([^\n]+)', oracle.stderr)}
    assert len(expected) == len(cases), 'Incomplete Zig binding oracle output'
    header = '''
import { parse as parse_sfc } from .compiler.parser.sfc.parse;
import { parse } from .compiler.parser.template.parse;
import { TemplateParseError } from .compiler.parser.template.errors;
import { normalize, NormalizeError } from .compiler.parser.template.normalize;
import { decode } from .compiler.sema.decode_script_facts;
import { bind } from .compiler.sema.bind_template;
import { TemplateBindings, BindingSource } from .compiler.sema.template_bindings;
import { ComponentManifests, ComponentSlotManifest } from .compiler.sema.component_manifests;
import { SlotManifest, SlotEntry } from .compiler.sema.slot_manifest;
import { text } from .compiler.sema.binding_context;
'''
    case_sources = []
    for i, (label, source, available) in enumerate(cases):
        outcome = expected[i]
        cy = []
        if outcome.startswith('OK '):
            record = json.loads(outcome[3:])
            expected_groups = list(groups(record['result']))
            for j, group in enumerate(expected_groups):
                cy.append(f'fn expect_{i}_{j}(source: []const u8, result: &const TemplateBindings): void {{')
                cy.extend(group)
                cy.append('}')
        cy.append(f'''test {cyna_literal(('binding corpus: ' + label).encode())} {{
    const source = {cyna_literal(source)};
    const sfc = parse_sfc(source.bytes()) catch (code) {{ panic("Expected SFC"); }};
    const bytes = source.bytes();
    const template = bytes[sfc.template.content_span.start..sfc.template.content_span.end];''')
        if outcome.startswith('PARSE '):
            error = re.sub(r'(?<!^)(?=[A-Z])', '_', outcome[6:]).lower()
            cy.append(f'    const raw = parse(template) catch (code) {{ assert(code == TemplateParseError.{error}); return; }}; assert(false);')
        else:
            cy.append('    const raw = parse(template) catch (code) { panic("Expected raw template"); };')
            if outcome.startswith('NORMALIZE '):
                error = re.sub(r'(?<!^)(?=[A-Z])', '_', outcome[10:]).lower()
                cy.append(f'    const normalized = normalize(&raw) catch (code) {{ assert(code == NormalizeError.{error}); return; }}; assert(false);')
            else:
                cy.append('    const normalized = normalize(&raw) catch (code) { panic("Expected normalization"); };')
                cy.append(f'    const decoded = decode({cyna_literal(record["payload"].encode())}) catch (code) {{ panic("Expected script facts"); }};')
                cy.append('    var catalogs: ComponentManifests = { entries: list<ComponentSlotManifest>() };')
                if available:
                    cy.append('''    var slots = list<SlotEntry>();
    slots.push(SlotEntry { name: "head", span: { start: 0, end: 0 } });
    catalogs.entries.push(ComponentSlotManifest { tag_name: "Card", manifest: SlotManifest { entries: slots } });''')
                cy.append('    const result = bind(template, &raw, &normalized, &decoded.facts, &catalogs);')
                for j in range(len(expected_groups)):
                    cy.append(f'    expect_{i}_{j}(template, &result);')
        cy.append('}')
        case_sources.append('\n'.join(cy))
    temporary_roots = []
    try:
        for start in range(0, len(case_sources), 8):
            fd, name = tempfile.mkstemp(prefix=f'binding_corpus_{start:03d}_', suffix='.test.cy', dir=ROOT / 'cyna-port/src')
            os.close(fd)
            temporary_roots.append(Path(name))
            Path(name).write_text(header + '\n'.join(case_sources[start:start + 8]))
        run([os.environ.get('CYNA', 'cyna'), 'test', str(ROOT / 'cyna-port'), '--jobs', '4'])
    finally:
        for root in temporary_roots:
            root.unlink(missing_ok=True)
    print(f'Template-binding parity passed: {len(paths)} components and {len(edges)} targeted inputs; references, calls, diagnostics/messages/spans and slot manifests compared ({time.monotonic() - started:.1f}s).')


if __name__ == '__main__':
    main()
