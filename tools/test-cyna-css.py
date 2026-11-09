#!/usr/bin/env python3
"""Optional live Zig parity for scope IDs, scoped CSS and supported emit diagnostics."""
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
HEADER = '''
import { compile_report, take_unit } from .compiler.compile;
import { ComponentManifests, ComponentSlotManifest } from .compiler.sema.component_manifests;
import { build } from .compiler.backend.browser.build_component;
import { compute } from .compiler.backend.browser.compute_scope_id;
import { emit, append_diagnostics, CssError } from .compiler.backend.browser.emit.emit_scoped_css;
import { CompilationDiagnostic, CompilationStage, SourceOrigin } from .compiler.diagnostics;
'''


def main():
    started = time.monotonic()
    paths = run(['git', 'ls-files', '*.weiv']).stdout.splitlines()
    cases = [(path, (ROOT / path).read_bytes()) for path in paths]
    edges = [
        '', ' \t\n', '/* { braces } */', '/* unterminated',
        'p{color:red}', '* > a{}', '.x:hover{}', '#app{}', '[role=button]{}', 'custom-element::part(x){}',
        'a, :is(.x,.y), [data-x="a,b"] { x:1; }', ', a, , {}', '{}',
        ':global( .x ){}', ':global(:is(a,b)), p{}', ':global(.x) .y{}', ':global(){}', ':global(.x)(.y){}',
        '@media (min-width:1px){p{a:b}}', '@supports (display:grid){@layer x{.a{}}}', '@layer reset;',
        '@keyframes k{from{opacity:0}to{opacity:1}}', '@font-face{font-family:x;src:url(x)}',
        '@container x{p{color:red}}', '@mediax{p{}}', '@scope (.x){p{}}',
        'p {content:"}";other:\'{\';}', '@import url("a;b{c}");p{}', 'p {content:"\\\"}";}',
        'p { /* } */ color:red; }', 'p { /* { */ color:red; }', 'p { /* comment */ color:red; }',
        'p', 'p {', 'p {x:"unterminated}', '@media x', '@media x{p{}', 'p[data-x="{"]', 'p{} }',
        '🌱 {content:"🌱"}', 'p{&:hover{color:red}}', '@media x{p{}}\n/* done */a{}',
    ]
    prefix = '<template><p>{{value}}</p></template><script lang="ts">export interface Props {} export let props: Props; export const value=1;</script><style>'
    cases += [(f'css-edge-{i}.weiv', (prefix + css + '</style>').encode()) for i, css in enumerate(edges)]
    lengths = [0, 1, 2, 3, 4, 7, 8, 15, 16, 17, 31, 32, 33, 47, 48, 49, 63, 64, 65, 95, 96, 97, 127, 128, 129, 144, 145, 256, 1024]
    hashes = [''.join(chr(33 + (j * 37) % 90) for j in range(n)) for n in lengths] + ['组件/🌱.weiv', './a.weiv', 'a.weiv', 'A.weiv']
    zig = [r'''
const std = @import("std");
const parser = @import("src/compiler/parser/index.zig");
const unit = @import("src/compiler/component_unit.zig");
const css = @import("src/compiler/backend/browser/emit/scoped_css.zig");
const diagnostics = @import("src/compiler/diagnostics.zig");
''']
    for i, (label, source) in enumerate(cases):
        zig.append(f'''test "CSS {i}" {{
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator); defer arena.deinit();
    const allocator = arena.allocator();
    const source = {literal(source)};
    var model: unit.ComponentUnit = undefined;
    model.source = source; model.source_path = {literal(label.encode())}; model.sfc_document = try parser.parseSfc(source);
    const scope = try css.scopeIdForPath(model.source_path, allocator);
    const output = css.emitScopedCss(&model, allocator) catch |err| {{
        var bag = diagnostics.DiagnosticBag.init();
        try css.appendEmitDiagnostics(&bag, &model, source, allocator);
        const record = try std.json.Stringify.valueAlloc(allocator, .{{ .scope = scope, .error_name = @errorName(err), .diagnostics = bag.diagnostics.items }}, .{{}});
        std.debug.print("\\nCSS {i} {{s}}\\n", .{{record}}); return;
    }};
    var bag = diagnostics.DiagnosticBag.init();
    try css.appendEmitDiagnostics(&bag, &model, source, allocator);
    const record = try std.json.Stringify.valueAlloc(allocator, .{{ .scope = scope, .output = output, .diagnostics = bag.diagnostics.items }}, .{{}});
    std.debug.print("\\nCSS {i} {{s}}\\n", .{{record}});
}}''')
    for i, path in enumerate(hashes):
        zig.append(f'''test "scope boundary {i}" {{
    const scope = try css.scopeIdForPath({literal(path.encode())}, std.testing.allocator); defer std.testing.allocator.free(scope);
    std.debug.print("\\nSCOPE {i} {{s}}\\n", .{{scope}});
}}''')
    fd, name = tempfile.mkstemp(prefix='.cyna-css-oracle-', suffix='.zig', dir=ROOT)
    os.close(fd)
    try:
        Path(name).write_text('\n'.join(zig))
        oracle = run([os.environ.get('ZIG', 'zig'), 'test', name])
    finally:
        Path(name).unlink(missing_ok=True)
    outcomes = {int(i): json.loads(record) for i, record in re.findall(r'CSS (\d+) ([^\n]+)', oracle.stderr)}
    scope_ids = {int(i): value for i, value in re.findall(r'SCOPE (\d+) ([^\n]+)', oracle.stderr)}
    assert len(outcomes) == len(cases) and len(scope_ids) == len(hashes), 'Incomplete CSS oracle'
    case_sources = []
    for i, (label, source) in enumerate(cases):
        expected = outcomes[i]
        cy = [f'''test {cyna_literal(('CSS corpus: ' + label).encode())} {{
    const catalogs: ComponentManifests = {{ entries: list<ComponentSlotManifest>() }};
    const source = {cyna_literal(source)};
    var report = compile_report(source, {cyna_literal(label.encode())}, &catalogs);
    const unit = take_unit(&report) catch (code) {{ panic("Expected complete unit"); }};
    const browser = build(unit);
    assert(browser.render_tree.nodes.len() == browser.unit.lir_document.nodes.len());
    assert(compute(browser.unit.source_path) == {cyna_literal(expected['scope'].encode())});
    var diagnostics = list<CompilationDiagnostic>();
    append_diagnostics(&browser.unit, &diagnostics);
    assert(diagnostics.len() == {len(expected['diagnostics'])});''']
        for j, diagnostic in enumerate(expected['diagnostics']):
            assert diagnostic['stage'] == 'emit', diagnostic
            cy.append(f'''    assert(diagnostics[{j}].stage == CompilationStage.emit);
    assert(diagnostics[{j}].origin == SourceOrigin.file);
    assert(diagnostics[{j}].severity == {cyna_literal(diagnostic['severity'].encode())});
    assert(diagnostics[{j}].code == {cyna_literal(diagnostic['code'].encode())});
    assert(diagnostics[{j}].message == {cyna_literal(diagnostic['message'].encode())});
    assert(diagnostics[{j}].fatal == {str(diagnostic['fatal']).lower()});''')
            span = diagnostic['span']
            cy.append(f'    if diagnostics[{j}].span is span {{ assert(span.start == {span["start"]}); assert(span.end == {span["end"]}); }} else {{ assert(false); }}')
        if 'error_name' in expected:
            assert expected['error_name'] == 'UnterminatedRule', expected
            cy.append('    const output = emit(&browser.unit) catch (code) { assert(code == CssError.unterminated_rule); return; }; assert(false);')
        else:
            cy.append('    const output = emit(&browser.unit) catch (code) { panic("Expected CSS"); };')
            cy.append(f'    assert(output == {cyna_literal(expected["output"].encode())});')
        cy.append('}')
        case_sources.append('\n'.join(cy))
    for i, path in enumerate(hashes):
        case_sources.append(f'''test "scope path boundary {i}" {{ assert(compute({cyna_literal(path.encode())}) == "{scope_ids[i]}"); }}''')
    temporary = []
    try:
        for start in range(0, len(case_sources), 8):
            fd, name = tempfile.mkstemp(prefix=f'css_corpus_{start:03d}_', suffix='.test.cy', dir=ROOT / 'cyna-port/src')
            os.close(fd)
            temporary.append(Path(name))
            Path(name).write_text(HEADER + '\n'.join(case_sources[start:start + 8]))
        run([os.environ.get('CYNA', 'cyna'), 'test', str(ROOT / 'cyna-port'), '--jobs', '4'])
    finally:
        for path in temporary:
            path.unlink(missing_ok=True)
    print(f'Scoped-CSS parity passed: {len(paths)} components + {len(edges)} targeted styles + {len(hashes)} path/hash boundaries; exact scope IDs, CSS bytes, typed errors and supported emit diagnostic fields checked ({time.monotonic() - started:.1f}s).')


if __name__ == '__main__':
    main()
