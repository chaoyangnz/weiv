#!/usr/bin/env python3
"""Optional live normalization comparison; everyday tests use cyna test."""
import os
from pathlib import Path
import re
import runpy
import tempfile

ROOT = Path(__file__).resolve().parents[1]
shared = runpy.run_path(str(ROOT / 'tools/test-cyna-template.py'))
run, literal, cyna_literal = (shared[name] for name in ('run', 'literal', 'cyna_literal'))

ZIG_SIGNATURE = shared['ZIG_ORACLE'].split('fn count(')[0] + r'''
const normalized = parser.template.normalized;
fn count(nodes: []const normalized.Node) usize {
    var total: usize = 0;
    for (nodes) |node| {
        total += 1;
        total += switch (node) {
            .element => |v| count(v.children),
            .slot_outlet => |v| count(v.fallback_children),
            .conditional => |v| count(v.consequent) + count(v.alternate),
            .for_loop => |v| count(v.body),
            else => 0,
        };
    }
    return total;
}
fn emit(nodes: []const normalized.Node, source: []const u8, next: *usize) void {
    for (nodes) |node| {
        const id = next.*; next.* += 1;
        switch (node) {
            .element => |v| {
                number(0); span(v.span); number(id + 1 + count(v.children));
                text(v.tag_name, source); number(v.attributes.len);
                for (v.attributes) |a| { text(a.name, source); maybe(a.value, source); span(a.span); }
                number(v.directives.len);
                for (v.directives) |d| switch (d) {
                    .event => |e| { number(3); text(e.event_name, source); text(e.expression, source); number(@intFromBool(e.deprecated_syntax)); span(e.span); },
                    .bind => |b| { number(4); text(b.target_name, source); text(b.expression, source); number(@intFromBool(b.deprecated_syntax)); span(b.span); },
                    .slot_assign => |s| { number(5); text(s.slot_name, source); span(s.span); },
                    else => @panic("normalization retained structural directive"),
                };
                emit(v.children, source, next);
            },
            .text => |v| { number(1); span(v.span); number(id + 1); },
            .interpolation => |v| { number(2); span(v.span); number(id + 1); text(v.expression, source); },
            .slot_outlet => |v| { number(3); span(v.span); number(id + 1 + count(v.fallback_children)); maybe(v.name, source); emit(v.fallback_children, source, next); },
            .conditional => |v| {
                number(4); span(v.span); number(id + 1 + count(v.consequent) + count(v.alternate));
                text(v.condition, source); number(id + 1 + count(v.consequent));
                emit(v.consequent, source, next); emit(v.alternate, source, next);
            },
            .for_loop => |v| {
                number(5); span(v.span); number(id + 1 + count(v.body));
                text(v.item_name, source); text(v.iterable_expr, source); emit(v.body, source, next);
            },
        }
    }
}
'''

CYNA_SIGNATURE = '''
import { normalize, NormalizeError } from .compiler.parser.template.normalize;
import { NormalizedDocument } from .compiler.parser.template.normalized;
import { TemplateElement, TemplateSlotOutlet } from .compiler.parser.template.ast;
''' + shared['CYNA_SIGNATURE'].split('fn signature(')[0] + '''
fn raw_element(raw: &const TemplateDocument, id: usize): TemplateElement {
    return switch raw.nodes[id].payload { .element(value) => value; _ => { panic("Expected raw element"); } };
}
fn raw_slot(raw: &const TemplateDocument, id: usize): TemplateSlotOutlet {
    return switch raw.nodes[id].payload { .slot_outlet(value) => value; _ => { panic("Expected raw slot"); } };
}
fn signature(raw: &const TemplateDocument, document: &const NormalizedDocument): List<usize> {
    var output = list<usize>();
    var id: usize = 0;
    while id < document.nodes.len() {
        const node = document.nodes[id];
        switch node.payload {
            .element(element) => {
                output.push(0); append_span(&output, node.span); output.push(node.subtree_end);
                const original = raw_element(raw, element.raw_node);
                append_span(&output, original.tag_name); output.push(original.attributes_count);
                var a = original.attributes_start;
                while a < original.attributes_start + original.attributes_count {
                    const attribute = raw.attributes[a];
                    append_span(&output, attribute.name); append_optional(&output, attribute.value); append_span(&output, attribute.span);
                    a = a + 1;
                }
                output.push(element.directives_count);
                var d = element.directives_start;
                while d < element.directives_start + element.directives_count {
                    const directive = raw.directives[document.directive_ids[d]];
                    switch directive.payload {
                        .event(value) => {
                            output.push(3); append_span(&output, value.name); append_span(&output, value.expression);
                            if value.deprecated_syntax { output.push(1); } else { output.push(0); }
                            append_span(&output, directive.span);
                        }
                        .bind(value) => {
                            output.push(4); append_span(&output, value.name); append_span(&output, value.expression);
                            if value.deprecated_syntax { output.push(1); } else { output.push(0); }
                            append_span(&output, directive.span);
                        }
                        .slot_assign(value) => { output.push(5); append_span(&output, value); append_span(&output, directive.span); }
                        _ => { panic("Normalization retained structural directive"); }
                    }
                    d = d + 1;
                }
            }
            .text(value) => { output.push(1); append_span(&output, node.span); output.push(node.subtree_end); }
            .interpolation(value) => { output.push(2); append_span(&output, node.span); output.push(node.subtree_end); append_span(&output, value); }
            .slot_outlet(raw_id) => {
                output.push(3); append_span(&output, node.span); output.push(node.subtree_end);
                append_optional(&output, raw_slot(raw, raw_id).name);
            }
            .conditional(value) => {
                output.push(4); append_span(&output, node.span); output.push(node.subtree_end);
                append_span(&output, value.condition); output.push(value.alternate_start);
            }
            .for_loop(value) => {
                output.push(5); append_span(&output, node.span); output.push(node.subtree_end);
                append_span(&output, value.item_name); append_span(&output, value.iterable_expr);
            }
        }
        id = id + 1;
    }
    return output;
}
'''


def main():
    paths = run(['git', 'ls-files', '*.weiv']).stdout.splitlines()
    cases = [(path, (ROOT / path).read_bytes()) for path in paths]
    edges = [
        '', '<a #if="x"/><b #else/><hr>', '<a #if="x"/>text<b #else/>',
        '<a #if="x"/>{{value}}<b #else/>', '<div><a #if="x"/></div><b #else/>',
        '<a #else/>', '<p #else #for="item in items"/>', '<p #else #if="x"/>',
        '<a #if="x" #for="item in items"/><b #else #if="y" #for="item in items"/>',
        '<a #if="first" #if="second"/><b #for="one in left" #for="two in right"/>',
        '<slot name="head"><a #if="x"/><b #else/></slot>',
        '<a #if="x"/><b #else><c #else/></b>', '<a #if="x" @click="go" :value="model" slot:head/>',
        '<ul><li #for="item in items"><a #if="item.ok"/><b #else/></li></ul>',
        '<p #if=""/>', '<p #if>',
    ]
    cases += [(f'normalization-edge-{i}', ('<template>' + source + '</template><script lang="ts"></script>').encode()) for i, source in enumerate(edges)]
    zig = [ZIG_SIGNATURE]
    for i, (_, source) in enumerate(cases):
        zig.append(f'''test "normalization-{i}" {{
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator); defer arena.deinit();
    const sections = parser.parseSfc({literal(source)}) catch {{ std.debug.print("\\nORACLE {i} SKIP\\n", .{{}}); return; }};
    const raw = parser.parseTemplate(sections.template.content, arena.allocator()) catch |err| {{
        std.debug.print("\\nORACLE {i} PARSE_ERROR {{s}}\\n", .{{@errorName(err)}}); return;
    }};
    const output = parser.normalizeTemplate(&raw, arena.allocator()) catch |err| {{
        std.debug.print("\\nORACLE {i} ERROR {{s}}\\n", .{{@errorName(err)}}); return;
    }};
    std.debug.print("\\nORACLE {i} OK", .{{}});
    var next: usize = 0; emit(output.nodes, sections.template.content, &next);
    std.debug.print("\\n", .{{}});
}}
''')
    with tempfile.TemporaryDirectory(prefix='weiv-normalize-oracle-') as scratch:
        oracle = Path(scratch) / 'oracle.zig'
        oracle.write_text('\n'.join(zig))
        result = run([os.environ.get('ZIG', 'zig'), 'test', '--dep', 'parser', f'-Mroot={oracle}', f'-Mparser={ROOT / "src/compiler/parser/index.zig"}'])
    expected = {int(i): value for i, value in re.findall(r'ORACLE (\d+) ([^\n]+)', result.stderr)}
    assert len(expected) == len(cases), 'Incomplete normalization oracle output'
    cy = [CYNA_SIGNATURE]
    skipped = 0
    for i, (label, source) in enumerate(cases):
        outcome = expected[i]
        if outcome == 'SKIP':
            skipped += 1
            continue
        cy.append(f'''test {cyna_literal(('normalization corpus: ' + label).encode())} {{
    const source = {cyna_literal(source)};
    const sections = parse_sfc(source.bytes()) catch (code) {{ panic("Expected SFC parse"); }};
    const bytes = source.bytes();
    const template_source = bytes[sections.template.content_span.start..sections.template.content_span.end];''')
        if outcome.startswith('PARSE_ERROR '):
            error = re.sub(r'(?<!^)(?=[A-Z])', '_', outcome[12:]).lower()
            cy.append(f'    const raw = parse(template_source) catch (code) {{ assert(code == TemplateParseError.{error}); return; }};\n    assert(false);')
        else:
            cy.append('    const raw = parse(template_source) catch (code) { panic("Expected template parse"); };')
            if outcome.startswith('ERROR '):
                error = re.sub(r'(?<!^)(?=[A-Z])', '_', outcome[6:]).lower()
                cy.append(f'    const output = normalize(&raw) catch (code) {{ assert(code == NormalizeError.{error}); return; }};\n    assert(false);')
            else:
                values = outcome[2:].split()
                cy.append('    const output = normalize(&raw) catch (code) { panic("Expected normalization"); };')
                cy.append(f'    const expected: [{len(values)}]usize = [{", ".join(values)}];')
                cy.append(f'    const actual = signature(&raw, &output);\n    assert(actual.len() == {len(values)});\n    var i: usize = 0;\n    while i < {len(values)} {{\n        if actual[i] != expected[i] {{ println(i); println(actual[i]); println(expected[i]); }}\n        assert(actual[i] == expected[i]); i = i + 1;\n    }}')
        cy.append('}')
    fd, name = tempfile.mkstemp(prefix='normalize_corpus_', suffix='.test.cy', dir=ROOT / 'cyna-port/src')
    os.close(fd)
    try:
        Path(name).write_text('\n'.join(cy))
        run([os.environ.get('CYNA', 'cyna'), 'test', str(ROOT / 'cyna-port')])
    finally:
        Path(name).unlink(missing_ok=True)
    print(f'Normalization parity passed: {len(paths)} components and {len(edges)} targeted inputs; {skipped} invalid SFC wrappers skipped.')


if __name__ == '__main__':
    main()
