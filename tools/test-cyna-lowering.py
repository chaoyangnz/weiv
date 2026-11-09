#!/usr/bin/env python3
"""Optional full template-lowering parity; native Cyna tests remain the default."""
import argparse
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


def groups(expected, render_tree=False):
    model_type = "RenderDocument" if render_tree else "LirDocument"
    helpers = []
    def span(path, value):
        return f'assert(text(source, {path}) == {cyna_literal(value.encode())});'
    def optional(path, value):
        if value is None:
            return f'if {path} is optional_value {{ assert(false); }}'
        return f'if {path} is optional_value {{ {span("optional_value", value)} }} else {{ assert(false); }}'
    def nodes(values, path):
        lines = [f'assert({path}.len() == {len(values)});']
        for i, value in enumerate(values):
            index = node(value)
            lines.append(f'node_CASE_{index}(source, result, {path}[{i}]);')
        return lines
    def effects(values, field):
        lines = [f'assert(value.{field}.len() == {len(values)});']
        for i, effect in enumerate(values):
            kind, data = next(iter(effect.items()))
            name = data.get('event_name', data.get('target_name'))
            lines += [f'const {field}_{i} = &value.{field}[{i}];', f'switch {field}_{i} {{ .{kind}(effect) => {{', span('effect.name', name), span('effect.expression', data['expression']), '} _ => { assert(false); } }']
        return lines
    def node(record):
        index = len(helpers)
        helpers.append(None)
        kind, data = next(iter(record.items()))
        lines = [f'fn node_CASE_{index}(source: []const u8, result: &const {model_type}, id: usize): void {{', 'const payload = &result.nodes[id].payload;', f'switch payload {{ .{kind}(value) => {{']
        if kind == 'text' or (kind == 'interpolation' and not render_tree):
            lines.append(span('value', data['content' if kind == 'text' else 'expression']))
        else:
            for key, value in data.items():
                path = 'value.' + key
                if key in ('effects', 'bind_effects', 'event_effects'): lines += effects(value, key)
                elif key in ('children', 'consequent', 'alternate', 'body', 'fallback_children'): lines += nodes(value, path)
                elif key == 'attributes':
                    lines.append(f'assert({path}.len() == {len(value)});')
                    for i, attr in enumerate(value):
                        lines += [span(f'{path}[{i}].name', attr['name']), optional(f'{path}[{i}].value', attr['value'])]
                elif key == 'slot_provisions':
                    lines.append(f'assert({path}.len() == {len(value)});')
                    for i, provision in enumerate(value):
                        lines.append(optional(f'{path}[{i}].name', provision['name']))
                        lines += nodes(provision['children'], f'{path}[{i}].children')
                elif isinstance(value, int): lines.append(f'assert({path} == {value});')
                elif key == 'name': lines.append(optional(path, value))
                else: lines.append(span(path, value))
        lines += ['} _ => { assert(false); } }', '}']
        helpers[index] = '\n'.join(lines)
        return index
    root = nodes(expected['nodes'], 'result.roots')
    root.append(f'assert(result.nodes.len() == {len(helpers)});')
    if render_tree:
        root.append(f'assert(result.next_ref_id == {expected["next_ref_id"]});')
    else:
        root.append(f'assert(result.expressions.len() == {len(expected["expressions"])});')
    groups = [root]
    for i, expr in enumerate(expected.get('expressions', [])):
        path = f'result.expressions[{i}]'
        lines = [span(path + '.source', expr['source']), f'assert({path}.references.len() == {len(expr["references"])});']
        for j, ref in enumerate(expr['references']):
            lines += [f'assert({path}.references[{j}].name == {cyna_literal(ref["name"].encode())});', f'assert({"" if ref["call"] else "not "}{path}.references[{j}].call);']
        groups.append(lines)
    return helpers, groups


def main():
    options = argparse.ArgumentParser(description=__doc__)
    options.add_argument('--coordinator', action='store_true', help='Exercise the complete in-memory compilation coordinator, including the live Rust backend.')
    options.add_argument('--render-tree', action='store_true', help='Compare browser render trees and reference allocation through the complete coordinator.')
    args = options.parse_args()
    if args.render_tree:
        args.coordinator = True
    model_type = 'RenderDocument' if args.render_tree else 'LirDocument'
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
    cases += [(f'lowering-edge-{i}', ('<template>' + template + '</template><script lang="ts">' + script + '</script>').encode(), available) for i, (template, available) in enumerate(edges)]
    edges += [(template, False) for template in [
        '<p slot:head/>', '<template/>', '<template slot:head/>',
        '<Card><template/></Card>', '<Card><template slot:head><i slot:other/></template></Card>',
        '<Card><p slot:head>A</p>one<b slot:head>B</b>two</Card>',
        '<Card><template slot:head @click="helper"><b/><i/></template><template slot:head/></Card>',
        '<Card><p slot:first slot:second @click="helper"/></Card>',
        '<Outer><Inner slot:head><b slot:body/></Inner></Outer>',
        '<p #if="user"><i #for="item in items">{{item}}</i></p><b #else/>',
        '<Card title="ignored" :title="user"/>', '<slot/>',
    ]]
    if args.render_tree:
        edges += [(template, False) for template in [
            '<div><b/>{{user}}</div><i/>',
            '<Card><b slot:head/>{{user}}<i slot:head/></Card>',
            '<Card><slot name="head"><i/>{{user}}</slot><Inner><b/></Inner></Card>',
            '<p #if="user"><Card><i/></Card></p><slot #else/>',
            '<p @click="helper" bind:title="user" @change="helper()" :value="user"/>',
            '<Card @pick="helper" bind:title="user"><template slot:head><b/></template></Card>',
            'hello 🌱', '',
        ]]
    # Append the additional lowering-only edge cases after the original set.
    cases += [(f'lowering-extra-{i}', ('<template>' + template + '</template><script lang="ts">' + script + '</script>').encode(), available) for i, (template, available) in enumerate(edges[13:])]
    zig = [ZIG_HEADER, 'const lowering = @import("src/compiler/lower/lower.zig");', 'const renderer = @import("src/compiler/backend/browser/render_tree/lower.zig");']
    for i, (label, source, available) in enumerate(cases):
        zig.append(f'''test "lowering {i}" {{
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator); defer arena.deinit();
    const allocator = arena.allocator();
    const sections = try parser.parseSfc({literal(source)});
    const raw = parser.parseTemplate(sections.template.content, allocator) catch |err| {{
        std.debug.print("\\nLOWER {i} PARSE {{s}}\\n", .{{@errorName(err)}}); return;
    }};
    const normalized = parser.normalizeTemplate(&raw, allocator) catch |err| {{
        std.debug.print("\\nLOWER {i} NORMALIZE {{s}}\\n", .{{@errorName(err)}}); return;
    }};
    const payload = try analyze(sections.script.content, {literal(label.encode())}, allocator);
    const decoded = try decoder.decode(payload, allocator);
    var entries = [_]slots.SlotEntry{{.{{ .name = "head", .span = .{{ .start = 0, .end = 0 }} }}}};
    var catalog = Catalog{{ .available = {str(available).lower()}, .manifest = .{{ .entries = &entries }} }};
    var provider = slots.Provider{{ .context = &catalog, .manifest_for = provide }};
    const bound = try binder.bind(&normalized, &decoded.facts, &provider, allocator);
    const lowered = lowering.lower(&normalized, &bound, allocator) catch |err| {{
        std.debug.print("\\nLOWER {i} LOWER {{s}} {{s}}\\n", .{{@errorName(err), payload}}); return;
    }};
    const result = {('try renderer.lower(&lowered, allocator)' if args.render_tree else 'lowered')};
    const encoded = try std.json.Stringify.valueAlloc(allocator, .{{ .payload = payload, .result = result }}, .{{}});
    std.debug.print("\\nLOWER {i} OK {{s}}\\n", .{{encoded}});
}}
''')
    fd, oracle_name = tempfile.mkstemp(prefix='.cyna-lowering-oracle-', suffix='.zig', dir=ROOT)
    os.close(fd)
    try:
        Path(oracle_name).write_text('\n'.join(zig))
        oracle = run([os.environ.get('ZIG', 'zig'), 'test', oracle_name, '-L', str(ROOT / 'libs/parser-backend/target/release'), '-lweiv_parser_backend', '-liconv', '-lc'])
    finally:
        Path(oracle_name).unlink(missing_ok=True)
    expected = {int(i): value for i, value in re.findall(r'LOWER (\d+) ([^\n]+)', oracle.stderr)}
    assert len(expected) == len(cases), 'Incomplete Zig lowering oracle output'
    header = '''
import { parse as parse_sfc } from .compiler.parser.sfc.parse;
import { parse } from .compiler.parser.template.parse;
import { TemplateParseError } from .compiler.parser.template.errors;
import { normalize, NormalizeError } from .compiler.parser.template.normalize;
import { decode } from .compiler.sema.decode_script_facts;
import { bind } from .compiler.sema.bind_template;
import { lower, LowerError } from .compiler.lower.lower_template;
import { compile_report, take_unit } from .compiler.compile;
import { CompilationStage } from .compiler.diagnostics;
import { LirDocument } from .compiler.lower.lir;
import { RenderDocument } from .compiler.backend.browser.render_tree.tree;
import { lower as render } from .compiler.backend.browser.render_tree.lower;
import { ComponentManifests, ComponentSlotManifest } from .compiler.sema.component_manifests;
import { SlotManifest, SlotEntry } from .compiler.sema.slot_manifest;
import { text } from .compiler.sema.binding_context;
'''
    case_sources = []
    for i, (label, source, available) in enumerate(cases):
        outcome = expected[i]
        cy = []
        if outcome.startswith('LOWER '):
            parts = outcome.split(' ', 2)
            record = {'payload': parts[2]}
            outcome = 'LOWER ' + parts[1]
        if outcome.startswith('OK '):
            record = json.loads(outcome[3:])
            node_helpers, expected_groups = groups(record['result'], args.render_tree)
            cy.extend(helper.replace('CASE', str(i)) for helper in node_helpers)
            for j, group in enumerate(expected_groups):
                cy.append(f'fn expect_{i}_{j}(source: []const u8, result: &const {model_type}): void {{')
                cy.extend(line.replace('CASE', str(i)) for line in group)
                cy.append('}')
        cy.append(f'''test {cyna_literal(('lowering corpus: ' + label).encode())} {{
    const source = {cyna_literal(source)};
    const sfc = parse_sfc(source.bytes()) catch (code) {{ panic("Expected SFC"); }};
    const bytes = source.bytes();
    const template = bytes[sfc.template.content_span.start..sfc.template.content_span.end];''')
        if args.coordinator:
            cy.append('    var catalogs: ComponentManifests = { entries: list<ComponentSlotManifest>() };')
            if available:
                cy.append('    var slots = list<SlotEntry>();\n    slots.push(SlotEntry { name: "head", span: { start: 0, end: 0 } });\n    catalogs.entries.push(ComponentSlotManifest { tag_name: "Card", manifest: SlotManifest { entries: slots } });')
            cy.append(f'    var report = compile_report(source, {cyna_literal(label.encode())}, &catalogs);')
            if outcome.startswith('OK '):
                cy.append('    if report.failure is failure { assert(false); }')
                cy.append('    const unit = take_unit(&report) catch (code) { panic("Expected complete unit"); };')
                cy.append('    const result = render(&unit.lir_document);' if args.render_tree else '    const result = unit.lir_document;')
                for j in range(len(expected_groups)):
                    cy.append(f'    expect_{i}_{j}(template, &result);')
            else:
                phase, name = outcome.split(' ', 1)
                stage = {'PARSE': 'template_parse', 'NORMALIZE': 'template_normalize', 'LOWER': 'lowering'}[phase]
                error = re.sub(r'(?<!^)(?=[A-Z])', '_', name).lower()
                cy.append(f'    if report.failure is failure {{ assert(failure.stage == CompilationStage.{stage}); assert(failure.code == "{error}"); }} else {{ assert(false); }}')
            cy.append('}')
            case_sources.append('\n'.join(cy))
            continue
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
                cy.append('    const bound = bind(template, &raw, &normalized, &decoded.facts, &catalogs);')
                if outcome.startswith('LOWER '):
                    error = re.sub(r'(?<!^)(?=[A-Z])', '_', outcome[6:]).lower()
                    cy.append(f'    const result = lower(template, &raw, &normalized, &bound) catch (code) {{ assert(code == LowerError.{error}); return; }}; assert(false);')
                    expected_groups = []
                else:
                    cy.append('    const result = lower(template, &raw, &normalized, &bound) catch (code) { panic("Expected lowering"); };')
                for j in range(len(expected_groups)):
                    cy.append(f'    expect_{i}_{j}(template, &result);')
        cy.append('}')
        case_sources.append('\n'.join(cy))
    temporary_roots = []
    try:
        for start in range(0, len(case_sources), 8):
            fd, name = tempfile.mkstemp(prefix=f'lowering_corpus_{start:03d}_', suffix='.test.cy', dir=ROOT / 'cyna-port/src')
            os.close(fd)
            temporary_roots.append(Path(name))
            Path(name).write_text(header + '\n'.join(case_sources[start:start + 8]))
        run([os.environ.get('CYNA', 'cyna'), 'test', str(ROOT / 'cyna-port'), '--jobs', '4'])
    finally:
        for root in temporary_roots:
            root.unlink(missing_ok=True)
    mode = 'Browser-render-tree' if args.render_tree else ('Compilation-coordinator' if args.coordinator else 'Template-lowering')
    compared = 'logical nodes, references, split effects, attributes and provisions' if args.render_tree else 'logical nodes, attributes, effects, provisions, expression references and hard placement errors'
    print(f'{mode} parity passed: {len(paths)} components and {len(edges)} targeted inputs; {compared} compared ({time.monotonic() - started:.1f}s).')


if __name__ == '__main__':
    main()
