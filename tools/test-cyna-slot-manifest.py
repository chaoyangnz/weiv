#!/usr/bin/env python3
"""Optional slot-manifest parity against Zig; permanent tests use cyna test."""
import json
import os
from pathlib import Path
import re
import runpy
import tempfile

ROOT = Path(__file__).resolve().parents[1]
helpers = runpy.run_path(str(ROOT / 'tools/test-cyna-sfc.py'))
run, literal, cyna_literal = (helpers[name] for name in ('run', 'literal', 'cyna_literal'))


def main():
    paths = run(['git', 'ls-files', '*.weiv']).stdout.splitlines()
    cases = [(path, (ROOT / path).read_bytes()) for path in paths]
    edges = [
        '', '<slot/>', '<slot name="header"/>',
        '<slot/><slot name=""/><slot name=""/><slot/>',
        '<slot name="x"/><slot name="x"/><slot name="x"/>',
        '<a #if="false"><slot name="x"/></a><b #else><slot name="x"/></b>',
        '<a #for="item in []"><slot/></a>',
        '<slot name="outer"><slot name="hidden"/></slot><slot name="after"/>',
        '<slot><a #if="x"><slot name="hidden"/></a><b #else><slot/></b></slot><slot/>',
        '<slot name="标题🌱"/>', '<Card slot:header/>',
        '<slot/><slot name="default"/><slot name="Header"/><slot name="header"/>',
    ]
    cases += [(f'slot-edge-{i}', ('<template>' + template + '</template><script lang="ts"></script>').encode()) for i, template in enumerate(edges)]
    zig = ['const std = @import("std");',
           'const parser = @import("src/compiler/parser/index.zig");',
           'const slots = @import("src/compiler/sema/slot_manifest.zig");']
    for i, (_, source) in enumerate(cases):
        zig.append(f'''test "slot manifest {i}" {{
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator); defer arena.deinit();
    const allocator = arena.allocator();
    const sections = try parser.parseSfc({literal(source)});
    const raw = parser.parseTemplate(sections.template.content, allocator) catch |err| {{
        std.debug.print("\\nSLOTS {i} PARSE {{s}}\\n", .{{@errorName(err)}}); return;
    }};
    const normalized = parser.normalizeTemplate(&raw, allocator) catch |err| {{
        std.debug.print("\\nSLOTS {i} NORMALIZE {{s}}\\n", .{{@errorName(err)}}); return;
    }};
    const report = try slots.build(&normalized, allocator);
    const encoded = try std.json.Stringify.valueAlloc(allocator, report, .{{}});
    std.debug.print("\\nSLOTS {i} OK {{s}}\\n", .{{encoded}});
}}
''')
    fd, oracle_name = tempfile.mkstemp(prefix='.cyna-slots-oracle-', suffix='.zig', dir=ROOT)
    os.close(fd)
    try:
        Path(oracle_name).write_text('\n'.join(zig))
        oracle = run([os.environ.get('ZIG', 'zig'), 'test', oracle_name])
    finally:
        Path(oracle_name).unlink(missing_ok=True)
    expected = {int(i): value for i, value in re.findall(r'SLOTS (\d+) ([^\n]+)', oracle.stderr)}
    assert len(expected) == len(cases), 'Incomplete Zig slot-manifest output'
    cy = ['import { parse as parse_sfc } from .compiler.parser.sfc.parse;',
          'import { parse } from .compiler.parser.template.parse;',
          'import { TemplateParseError } from .compiler.parser.template.errors;',
          'import { normalize, NormalizeError } from .compiler.parser.template.normalize;',
          'import { build } from .compiler.sema.build_slot_manifest;']
    for i, (label, source) in enumerate(cases):
        outcome = expected[i]
        cy.append(f'''test {cyna_literal(('slot corpus: ' + label).encode())} {{
    const source = {cyna_literal(source)};
    const sections = parse_sfc(source.bytes()) catch (code) {{ panic("Expected SFC"); }};
    const bytes = source.bytes();
    const template = bytes[sections.template.content_span.start..sections.template.content_span.end];''')
        if outcome.startswith('PARSE '):
            error = re.sub(r'(?<!^)(?=[A-Z])', '_', outcome[6:]).lower()
            cy.append(f'    const raw = parse(template) catch (code) {{ assert(code == TemplateParseError.{error}); return; }};\n    assert(false);')
        else:
            cy.append('    const raw = parse(template) catch (code) { panic("Expected raw template"); };')
            if outcome.startswith('NORMALIZE '):
                error = re.sub(r'(?<!^)(?=[A-Z])', '_', outcome[10:]).lower()
                cy.append(f'    const normalized = normalize(&raw) catch (code) {{ assert(code == NormalizeError.{error}); return; }};\n    assert(false);')
            else:
                cy.append('    const normalized = normalize(&raw) catch (code) { panic("Expected normalization"); };')
                cy.append('    const result = build(template, &raw, &normalized);')
                report = json.loads(outcome[3:])
                for field, records in [('manifest.entries', report['manifest']['entries']), ('duplicates', report['duplicates'])]:
                    cy.append(f'    assert(result.{field}.len() == {len(records)});')
                    for index, record in enumerate(records):
                        access = f'result.{field}[{index}]'
                        if record['name'] is None:
                            cy.append(f'    if {access}.name is unexpected {{ assert(false); }}')
                        else:
                            cy.append(f'    if {access}.name is name {{ assert(name == {cyna_literal(record["name"].encode())}); }} else {{ assert(false); }}')
                        cy.append(f'    assert({access}.span.start == {record["span"]["start"]});')
                        cy.append(f'    assert({access}.span.end == {record["span"]["end"]});')
        cy.append('}')
    fd, name = tempfile.mkstemp(prefix='slot_manifest_corpus_', suffix='.test.cy', dir=ROOT / 'cyna-port/src')
    os.close(fd)
    try:
        Path(name).write_text('\n'.join(cy))
        run([os.environ.get('CYNA', 'cyna'), 'test', str(ROOT / 'cyna-port')])
    finally:
        Path(name).unlink(missing_ok=True)
    print(f'Slot-manifest parity passed: {len(paths)} components and {len(edges)} targeted inputs; all entries, duplicate names and spans compared.')


if __name__ == '__main__':
    main()
