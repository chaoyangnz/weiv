#!/usr/bin/env python3
"""Optional Zig/Cyna typed-script-fact parity on the tracked component corpus."""
import argparse
import json
import os
from pathlib import Path
import re
import runpy
import tempfile
import time

ROOT = Path(__file__).resolve().parents[1]
shared = runpy.run_path(str(ROOT / 'tools/test-cyna-sfc.py'))
run, literal, cyna_literal = (shared[name] for name in ('run', 'literal', 'cyna_literal'))
OPTIONAL_FIELDS = {'props', 'props_binding_name', 'props_type_name', 'imported_name', 'type_annotation', 'code', 'member_path'}
SPAN_FIELDS = {'span_start': 'span.start', 'span_end': 'span.end', 'callback_span_start': 'span.start', 'callback_span_end': 'span.end'}


def assertions(value, path, output, counter):
    if isinstance(value, dict):
        for key, item in value.items():
            child = path + '.' + SPAN_FIELDS.get(key, key)
            if key in OPTIONAL_FIELDS:
                name = f'optional_{counter[0]}'
                counter[0] += 1
                if item is None:
                    output.append(f'    if {child} is {name} {{ assert(false); }}')
                else:
                    output.append(f'    if {child} is {name} {{')
                    assertions(item, name, output, counter)
                    output.append('    } else { assert(false); }')
            else:
                assertions(item, child, output, counter)
    elif isinstance(value, list):
        output.append(f'    assert({path}.len() == {len(value)});')
        for index, item in enumerate(value):
            assertions(item, f'{path}[{index}]', output, counter)
    elif isinstance(value, bool):
        output.append(f'    assert({"" if value else "not "}{path});')
    elif isinstance(value, int):
        output.append(f'    assert({path} == {value});')
    elif isinstance(value, str):
        output.append(f'    assert({path} == {cyna_literal(value.encode())});')
    else:
        raise AssertionError(f'Unhandled oracle value at {path}: {value!r}')


def assertion_groups(value, path, counter):
    # Bound ownership-analysis work per generated function instead of putting
    # thousands of deep projections in a single test body.
    if isinstance(value, dict) and path in ('result', 'result.facts', 'result.facts.state_facts'):
        for key, item in value.items():
            if key in OPTIONAL_FIELDS:
                group = []
                assertions({key: item}, path, group, counter)
                yield group
            else:
                yield from assertion_groups(item, path + '.' + key, counter)
    elif isinstance(value, list):
        yield [f'    assert({path}.len() == {len(value)});']
        for index, item in enumerate(value):
            group = []
            assertions(item, f'{path}[{index}]', group, counter)
            yield group
    else:
        group = []
        assertions(value, path, group, counter)
        yield group


def main():
    options = argparse.ArgumentParser(description=__doc__)
    options.add_argument('--batch-size', type=int, default=8, help='components per generated Cyna test root')
    options.add_argument('--jobs', type=int, default=4, help='Cyna native test compilation workers')
    args = options.parse_args()
    if args.batch_size < 1 or args.jobs < 1:
        options.error('batch size and jobs must be positive')
    started = time.monotonic()
    paths = run(['git', 'ls-files', '*.weiv']).stdout.splitlines()
    zig = ['const std = @import("std");',
           'const sfc = @import("src/compiler/parser/sfc.zig");',
           '''
extern fn weiv_script_analyze(source: [*:0]const u8, path: [*:0]const u8) ?[*:0]u8;
extern fn weiv_backend_free(pointer: [*:0]u8) void;
fn analyze_raw(source: []const u8, path: []const u8, allocator: std.mem.Allocator) ![]u8 {
    // Equivalent transport: current Zig uses dupeSentinel instead of dupeZ.
    const source_z = try allocator.dupeSentinel(u8, source, 0);
    defer allocator.free(source_z);
    const path_z = try allocator.dupeSentinel(u8, path, 0);
    defer allocator.free(path_z);
    const result = weiv_script_analyze(source_z.ptr, path_z.ptr) orelse return error.BackendFailure;
    defer weiv_backend_free(result);
    return try allocator.dupe(u8, std.mem.span(result));
}
''',
           'const decoder = @import("src/compiler/sema/decode_script_facts.zig");',
           'test { _ = @import("cyna-port/reference/script_decode.zig"); }']
    for i, path in enumerate(paths):
        zig.append(f'''test "script facts {i}" {{
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator); defer arena.deinit();
    const allocator = arena.allocator();
    const sections = try sfc.parse({literal((ROOT / path).read_bytes())});
    const payload = try analyze_raw(sections.script.content, {literal(path.encode())}, allocator);
    const expected = try decoder.decode(payload, allocator);
    const encoded = try std.json.Stringify.valueAlloc(allocator, .{{ .payload = payload, .expected = expected }}, .{{}});
    std.debug.print("\\nFACTS {i} {{s}}\\n", .{{encoded}});
}}
''')
    fd, oracle_name = tempfile.mkstemp(prefix='.cyna-script-oracle-', suffix='.zig', dir=ROOT)
    os.close(fd)
    try:
        Path(oracle_name).write_text('\n'.join(zig))
        oracle = run([os.environ.get('ZIG', 'zig'), 'test', oracle_name,
                      '-L', str(ROOT / 'libs/parser-backend/target/release'),
                      '-lweiv_parser_backend', '-liconv', '-lc'])
    finally:
        Path(oracle_name).unlink(missing_ok=True)
    expected = {int(i): json.loads(value) for i, value in re.findall(r'FACTS (\d+) ([^\n]+)', oracle.stderr)}
    assert len(expected) == len(paths), 'Incomplete typed script-fact oracle output'
    header = ['import { decode } from .compiler.sema.decode_script_facts;',
              'import { DecodedScript } from .compiler.sema.decoded_script;']
    case_sources = []
    for i, path in enumerate(paths):
        record = expected[i]
        cy = []
        groups = list(assertion_groups(record['expected'], 'result', [0]))
        for group_id, group in enumerate(groups):
            cy.append(f'fn expect_{i}_{group_id}(result: &const DecodedScript): void {{')
            cy.extend(group)
            cy.append('}')
        cy.append(f'test {cyna_literal(("script-fact corpus: " + path).encode())} {{')
        cy.append(f'    const result = decode({cyna_literal(record["payload"].encode())}) catch (code) {{ panic("Expected canonical Rust schema"); }};')
        for group_id in range(len(groups)):
            cy.append(f'    expect_{i}_{group_id}(&result);')
        cy.append('}')
        case_sources.append('\n'.join(cy))
    oracle_seconds = time.monotonic() - started
    test_started = time.monotonic()
    temporary_roots = []
    try:
        for batch in range(0, len(case_sources), args.batch_size):
            fd, name = tempfile.mkstemp(prefix=f'script_facts_corpus_{batch:03d}_', suffix='.test.cy', dir=ROOT / 'cyna-port/src')
            os.close(fd)
            temporary_roots.append(Path(name))
            Path(name).write_text('\n'.join(header + case_sources[batch:batch + args.batch_size]))
        run([os.environ.get('CYNA', 'cyna'), 'test', str(ROOT / 'cyna-port'), '--jobs', str(args.jobs)])
    finally:
        for root in temporary_roots:
            root.unlink(missing_ok=True)
    print(f'Typed script-fact parity passed: {len(paths)} components, all decoded fields and transpiled code compared.')
    print(f'Oracle/schema phase: {oracle_seconds:.1f}s; Cyna comparison: {time.monotonic() - test_started:.1f}s (batch size {args.batch_size}, jobs {args.jobs}).')



if __name__ == '__main__':
    main()
