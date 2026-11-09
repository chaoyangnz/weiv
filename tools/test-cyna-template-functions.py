#!/usr/bin/env python3
"""Optional Zig evaluator parity, with exact source-pointer mappings as a separate oracle."""
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

# Minimal retained ABI adapter uses Zig 0.17's dupeSentinel spelling. The real
# collector/append implementation is copied unchanged except its import path.
BACKEND = r'''
const std = @import("std");
extern fn weiv_cell_handler_supported(source: [*:0]const u8) bool;
extern fn weiv_cell_handler_kind(source: [*:0]const u8) u8;
extern fn weiv_analyze_module_state(source: [*:0]const u8, path: [*:0]const u8) ?[*:0]u8;
extern fn weiv_backend_free(pointer: [*:0]u8) void;
pub fn validateCellHandlerExpression(source: []const u8, allocator: std.mem.Allocator) !void {
    const z = try allocator.dupeSentinel(u8, source, 0); defer allocator.free(z);
    if (!weiv_cell_handler_supported(z.ptr)) return error.CellTemplateExpressionUnsupported;
}
pub fn cellHandlerKind(source: []const u8, allocator: std.mem.Allocator) !u8 {
    const z = try allocator.dupeSentinel(u8, source, 0); defer allocator.free(z);
    return weiv_cell_handler_kind(z.ptr);
}
pub fn analyzeModuleStateRaw(source: []const u8, path: []const u8, allocator: std.mem.Allocator) ![]u8 {
    const z = try allocator.dupeSentinel(u8, source, 0); defer allocator.free(z);
    const p = try allocator.dupeSentinel(u8, path, 0); defer allocator.free(p);
    const result = weiv_analyze_module_state(z.ptr, p.ptr) orelse return error.BackendFailure;
    defer weiv_backend_free(result);
    return allocator.dupe(u8, std.mem.span(result));
}
'''
HEADER = '''
import { parse as parse_sfc } from .compiler.parser.sfc.parse;
import { parse } from .compiler.parser.template.parse;
import { normalize } from .compiler.parser.template.normalize;
import { decode } from .compiler.sema.decode_script_facts;
import { collect } from .compiler.lower.collect_template_functions;
import { build, TemplateFunctionError } from .compiler.lower.build_template_functions;
import { TemplateFunctions } from .compiler.lower.template_functions;
import { text } from .compiler.sema.binding_context;
'''


def temporary(parent, prefix, suffix, contents, cleanup):
    fd, name = tempfile.mkstemp(prefix=prefix, suffix=suffix, dir=parent)
    os.close(fd)
    path = Path(name)
    cleanup.append(path)
    path.write_text(contents)
    return path


def main():
    started = time.monotonic()
    paths = run(['git', 'ls-files', '*.weiv']).stdout.splitlines()
    cases = [(path, (ROOT / path).read_bytes()) for path in paths]
    edges = [
        '<a #if="a">{{a}}</a>{{a}}',
        '<p #for="item in items">{{item}}<i #for="item in item.children" @click="item.run"/></p>{{outside}}',
        '<Card @pick="ok ? save : false"><p @click="save"/></Card>',
        '<p @click="count++" @change="save()" bind:title="count++"/>{{value}}',
        '<p #for="event in items" @click="event"/>',
        '<p #for="payload in items"><Card @pick="payload"/></p>',
        '<Card><template slot:head @click="save">{{value}}</template></Card>',
        '<p #if="ok"><i #for="item in items">{{item}}</i></p><b #else>{{other}}</b>',
        '<slot>{{count++}}<p @click="save"/></slot>',
        '{{await foo()}}{{value}}', '{{count++}}{{value}}{{count++}}',
        '<p #for="__weiv_bad in items" @click="save"/>',
        '<p @click="ok && save"/><p @click="(count++, save)"/>',
        '<p @click="x => x + 1"/><p @click="obj.handler"/>',
        '<p/>',
        '{{"🌱"}}{{value}}',
    ]
    script = "import { value as imported } from './m'; export interface Props {} export let props: Props; export const event = 1; export const payload = 2; export let count = 0; export const items = [];"
    cases += [(f'functions-edge-{i}', ('<template>' + template + '</template><script lang="ts">' + script + '</script>').encode()) for i, template in enumerate(edges)]
    cleanup = []
    try:
        backend = temporary(ROOT / 'src/ffi', '.cyna-functions-backend-', '.zig', BACKEND, cleanup)
        reference = (ROOT / 'src/compiler/lower/template_functions.zig').read_text().replace('../../ffi/script_backend.zig', '../../ffi/' + backend.name)
        original = temporary(ROOT / 'src/compiler/lower', '.cyna-functions-original-', '.zig', reference, cleanup)
        # This independent pointer identity oracle replaces only the legacy text
        # search, so exact parser offsets can be checked without copying Cyna code.
        fixed = reference.replace('std.mem.indexOfPos(u8, self.template, start, source) orelse start', '@intFromPtr(source.ptr) - @intFromPtr(self.template.ptr)').replace('source: []const u8, start: usize, argument:', 'source: []const u8, _: usize, argument:')
        exact = temporary(ROOT / 'src/compiler/lower', '.cyna-functions-exact-', '.zig', fixed, cleanup)
        zig = [ZIG_HEADER, f'const functions = @import("src/compiler/lower/{original.name}");', f'const exact = @import("src/compiler/lower/{exact.name}");']
        for i, (label, source) in enumerate(cases):
            zig.append(f'''test "functions {i}" {{
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator); defer arena.deinit();
    const allocator = arena.allocator();
    const sections = try parser.parseSfc({literal(source)});
    const raw = try parser.parseTemplate(sections.template.content, allocator);
    const normalized = try parser.normalizeTemplate(&raw, allocator);
    const payload = try analyze(sections.script.content, {literal(label.encode())}, allocator);
    const decoded = try decoder.decode(payload, allocator);
    const names = try functions.bindingNames(&decoded.facts, allocator);
    for ([_]bool{{ false, true }}) |pure| {{
        var code = std.ArrayList(u8).empty;
        try code.appendSlice(allocator, "prefix[");
        var collector = functions.Collector{{ .allocator = allocator, .script = &code, .template = sections.template.content, .script_names = names, .include_pure = pure }};
        collector.walk(normalized.nodes) catch |err| {{
            std.debug.print("\\nFUNCTIONS {i} {{d}} ERROR {{s}}\\n", .{{@intFromBool(pure), @errorName(err)}}); continue;
        }};
        var corrected = std.ArrayList(u8).empty;
        try corrected.appendSlice(allocator, "prefix[");
        var mapped = exact.Collector{{ .allocator = allocator, .script = &corrected, .template = sections.template.content, .script_names = names, .include_pure = pure }};
        try mapped.walk(normalized.nodes);
        try std.testing.expectEqualStrings(code.items, corrected.items);
        const encoded = try std.json.Stringify.valueAlloc(allocator, .{{ .payload = payload, .names = names, .code = code.items, .records = mapped.records.items, .legacy_records = collector.records.items }}, .{{}});
        std.debug.print("\\nFUNCTIONS {i} {{d}} OK {{s}}\\n", .{{ @intFromBool(pure), encoded }});
    }}
}}''')
        oracle_file = temporary(ROOT, '.cyna-functions-oracle-', '.zig', '\n'.join(zig), cleanup)
        oracle = run([os.environ.get('ZIG', 'zig'), 'test', str(oracle_file), '-L', str(ROOT / 'libs/parser-backend/target/release'), '-lweiv_parser_backend', '-liconv', '-lc'])
        outcomes = {(int(i), int(pure)): outcome for i, pure, outcome in re.findall(r'FUNCTIONS (\d+) (\d) ([^\n]+)', oracle.stderr)}
        assert len(outcomes) == len(cases) * 2, 'Incomplete function oracle'
        case_sources = []
        corrections = 0
        for i, (label, source) in enumerate(cases):
            # Reserved-identifier failures still need decoded facts; use a
            # successful sibling outcome, or obtain facts from the source ABI.
            successful = [outcomes[i, pure] for pure in (0, 1) if outcomes[i, pure].startswith('OK ')]
            if successful:
                payload = json.loads(successful[0][3:])['payload']
                decode_line = f'const decoded = decode({cyna_literal(payload.encode())}) catch (code) {{ panic("Expected script facts"); }};'
            else:
                decode_line = 'const payload = analyze_raw(script, "functions.weiv") catch (code) { panic("Expected backend"); }; const decoded = decode(payload) catch (code) { panic("Expected script facts"); };'
            for pure in (0, 1):
                outcome = outcomes[i, pure]
                cy = []
                if outcome.startswith('OK '):
                    result = json.loads(outcome[3:])
                    corrections += sum(a != b for a, b in zip(result['records'], result['legacy_records']))
                    # Small helpers avoid the known large-root compilation cost.
                    for j, record in enumerate(result['records']):
                        cy.append(f'''fn expect_{i}_{pure}_{j}(source: []const u8, result: &const TemplateFunctions): void {{
    const record = &result.records[{j}];
    assert(record.generated.start == {record['generated']['start']});
    assert(record.generated.end == {record['generated']['end']});
    assert(record.template.start == {record['template']['start']});
    assert(record.template.end == {record['template']['end']});
    assert(text(result.code.bytes(), record.generated) == text(source, record.template));
}}''')
                cy.append(f'''test {cyna_literal((label + (' all' if pure else ' mutations')).encode())} {{
    const source = {cyna_literal(source)};
    const sfc = parse_sfc(source.bytes()) catch (code) {{ panic("Expected SFC"); }};
    const bytes = source.bytes();
    const template = bytes[sfc.template.content_span.start..sfc.template.content_span.end];
    const script = string.from(bytes[sfc.script.content_span.start..sfc.script.content_span.end]);
    {decode_line}
    const raw = parse(template) catch (code) {{ panic("Expected template"); }};
    const normalized = normalize(&raw) catch (code) {{ panic("Expected normalization"); }};
    const inputs = collect(template, &raw, &normalized, &decoded.facts);''')
                if outcome.startswith('ERROR '):
                    assert outcome == 'ERROR CellReservedIdentifier', outcome
                    cy.append(f'''    const result = build(template, &inputs, {str(bool(pure)).lower()}, "prefix[") catch (code) {{ assert(code == TemplateFunctionError.reserved_identifier); return; }}; assert(false);''')
                else:
                    cy.append(f'    assert(inputs.script_names.len() == {len(result["names"])});')
                    for j, name in enumerate(result['names']):
                        cy.append(f'    assert(inputs.script_names[{j}] == {cyna_literal(name.encode())});')
                    cy.append(f'    const result = build(template, &inputs, {str(bool(pure)).lower()}, "prefix[") catch (code) {{ panic("Expected functions"); }};')
                    cy.append(f'    assert(result.code == {cyna_literal(result["code"].encode())});')
                    cy.append(f'    assert(result.records.len() == {len(result["records"])});')
                    for j in range(len(result['records'])):
                        cy.append(f'    expect_{i}_{pure}_{j}(template, &result);')
                cy.append('}')
                case_sources.append('\n'.join(cy))
        for start in range(0, len(case_sources), 8):
            temporary(ROOT / 'cyna-port/src', f'function_corpus_{start:03d}_', '.test.cy', HEADER + '\nimport { analyze_raw } from .ffi.script_backend;\n' + '\n'.join(case_sources[start:start + 8]), cleanup)
        run([os.environ.get('CYNA', 'cyna'), 'test', str(ROOT / 'cyna-port'), '--jobs', '4'])
    finally:
        for path in reversed(cleanup):
            path.unlink(missing_ok=True)
    print(f'Template-function parity passed: {len(paths)} components + {len(edges)} targeted inputs, both selection modes; generated bytes, binding names, errors and exact source mappings checked. {corrections} legacy mapping records corrected ({time.monotonic() - started:.1f}s).')


if __name__ == '__main__':
    main()
