#!/usr/bin/env python3
"""Optional live Zig/Cyna template comparison; ordinary tests use cyna test."""
import os
from pathlib import Path
import re
import runpy
import tempfile

ROOT = Path(__file__).resolve().parents[1]
helpers = runpy.run_path(str(ROOT / 'tools/test-cyna-sfc.py'))
run = helpers['run']
literal = helpers['literal']
cyna_literal = helpers['cyna_literal']

ZIG_ORACLE = r'''
const std = @import("std");
const parser = @import("parser");
const ast = parser.template.ast;
fn number(value: usize) void { std.debug.print(" {d}", .{value}); }
fn span(value: parser.sfc.Span) void { number(value.start); number(value.end); }
fn text(value: []const u8, source: []const u8) void {
    const start = @intFromPtr(value.ptr) - @intFromPtr(source.ptr);
    number(start); number(start + value.len);
}
fn maybe(value: ?[]const u8, source: []const u8) void {
    number(@intFromBool(value != null));
    if (value) |v| text(v, source);
}
fn count(nodes: []const ast.Node) usize {
    var size: usize = 0;
    for (nodes) |node| {
        size += 1;
        switch (node) {
            .element => |v| size += count(v.children),
            .slot_outlet => |v| size += count(v.fallback_children),
            else => {},
        }
    }
    return size;
}
fn emit(nodes: []const ast.Node, source: []const u8, next: *usize) void {
    for (nodes) |node| {
        const id = next.*;
        next.* += 1;
        switch (node) {
            .element => |v| {
                number(0); span(v.span); number(id + 1 + count(v.children));
                text(v.tag_name, source); number(v.attributes.len);
                for (v.attributes) |attribute| {
                    text(attribute.name, source); maybe(attribute.value, source); span(attribute.span);
                }
                number(v.directives.len);
                for (v.directives) |directive| switch (directive) {
                    .if_expr => |d| { number(0); text(d.expression, source); },
                    .else_branch => { number(1); },
                    .for_expr => |d| { number(2); text(d.item_name, source); text(d.iterable_expr, source); },
                    .event => |d| { number(3); text(d.event_name, source); text(d.expression, source); number(@intFromBool(d.deprecated_syntax)); span(d.span); },
                    .bind => |d| { number(4); text(d.target_name, source); text(d.expression, source); number(@intFromBool(d.deprecated_syntax)); span(d.span); },
                    .slot_assign => |d| { number(5); text(d.slot_name, source); span(d.span); },
                };
                emit(v.children, source, next);
            },
            .text => |v| { number(1); span(v.span); number(id + 1); },
            .interpolation => |v| { number(2); span(v.span); number(id + 1); text(v.expression, source); },
            .slot_outlet => |v| {
                number(3); span(v.span); number(id + 1 + count(v.fallback_children));
                maybe(v.name, source); emit(v.fallback_children, source, next);
            },
        }
    }
}
'''

CYNA_SIGNATURE = '''
import { parse as parse_sfc } from .compiler.parser.sfc.parse;
import { parse } from .compiler.parser.template.parse;
import { TemplateParseError } from .compiler.parser.template.errors;
import { TemplateDocument } from .compiler.parser.template.ast;
import { Span } from .compiler.source;
fn append_span(output: &List<usize>, span: Span): void {
    output.push(span.start); output.push(span.end);
}
fn append_optional(output: &List<usize>, span: ?Span): void {
    if span is value { output.push(1); append_span(output, value); }
    else { output.push(0); }
}
fn signature(document: &const TemplateDocument): List<usize> {
    var output = list<usize>();
    var id: usize = 0;
    while id < document.nodes.len() {
        const node = document.nodes[id];
        switch node.payload {
            .element(element) => {
                output.push(0); append_span(&output, node.span); output.push(node.subtree_end);
                append_span(&output, element.tag_name); output.push(element.attributes_count);
                var a = element.attributes_start;
                while a < element.attributes_start + element.attributes_count {
                    const attribute = document.attributes[a];
                    append_span(&output, attribute.name); append_optional(&output, attribute.value); append_span(&output, attribute.span);
                    a = a + 1;
                }
                output.push(element.directives_count);
                var d = element.directives_start;
                while d < element.directives_start + element.directives_count {
                    const directive = document.directives[d];
                    switch directive.payload {
                        .if_expr(value) => { output.push(0); append_span(&output, value); }
                        .else_branch => { output.push(1); }
                        .for_expr(value) => { output.push(2); append_span(&output, value.item_name); append_span(&output, value.iterable_expr); }
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
                    }
                    d = d + 1;
                }
            }
            .text(value) => { output.push(1); append_span(&output, node.span); output.push(node.subtree_end); }
            .interpolation(value) => { output.push(2); append_span(&output, node.span); output.push(node.subtree_end); append_span(&output, value); }
            .slot_outlet(value) => { output.push(3); append_span(&output, node.span); output.push(node.subtree_end); append_optional(&output, value.name); }
        }
        id = id + 1;
    }
    return output;
}
'''


def main():
    paths = run(['git', 'ls-files', '*.weiv']).stdout.splitlines()
    cases = [(path, (ROOT / path).read_bytes()) for path in paths]
    zig = [ZIG_ORACLE]
    for i, (_, source) in enumerate(cases):
        zig.append(f'''test "component-{i}" {{
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const sections = parser.parseSfc({literal(source)}) catch {{
        std.debug.print("\\nORACLE {i} SKIP\\n", .{{}}); return;
    }};
    const document = parser.parseTemplate(sections.template.content, arena.allocator()) catch |err| {{
        std.debug.print("\\nORACLE {i} ERROR {{s}}\\n", .{{@errorName(err)}}); return;
    }};
    std.debug.print("\\nORACLE {i} OK", .{{}});
    var next: usize = 0;
    emit(document.nodes, sections.template.content, &next);
    std.debug.print("\\n", .{{}});
}}
''')
    with tempfile.TemporaryDirectory(prefix='weiv-template-oracle-') as scratch:
        oracle = Path(scratch) / 'oracle.zig'
        oracle.write_text('\n'.join(zig))
        result = run([os.environ.get('ZIG', 'zig'), 'test', '--dep', 'parser',
                      f'-Mroot={oracle}', f'-Mparser={ROOT / "src/compiler/parser/index.zig"}'])
    expected = {int(i): value for i, value in re.findall(r'ORACLE (\d+) ([^\n]+)', result.stderr)}
    assert len(expected) == len(cases), 'Incomplete Zig oracle output'
    cy = [CYNA_SIGNATURE]
    skipped = 0
    for i, (label, source) in enumerate(cases):
        outcome = expected[i]
        if outcome == 'SKIP':
            skipped += 1
            continue
        cy.append(f'''test {cyna_literal(('template corpus: ' + label).encode())} {{
    const source = {cyna_literal(source)};
    const sections = parse_sfc(source.bytes()) catch (code) {{ panic("Expected SFC parse"); }};
    const bytes = source.bytes();
    const template_source = bytes[sections.template.content_span.start..sections.template.content_span.end];''')
        if outcome.startswith('ERROR '):
            error = re.sub(r'(?<!^)(?=[A-Z])', '_', outcome[6:]).lower()
            cy.append(f'''    const document = parse(template_source) catch (code) {{ assert(code == TemplateParseError.{error}); return; }};
    assert(false);''')
        else:
            values = outcome[2:].split()
            cy.append('    const document = parse(template_source) catch (code) { panic("Expected template parse"); };')
            cy.append(f'    const expected: [{len(values)}]usize = [{", ".join(values)}];')
            cy.append('''    const actual = signature(&document);
    assert(actual.len() == EXPECTED_LENGTH);
    var index: usize = 0;
    while index < EXPECTED_LENGTH {
        if actual[index] != expected[index] { println(index); println(actual[index]); println(expected[index]); }
        assert(actual[index] == expected[index]); index = index + 1;
    }'''.replace('EXPECTED_LENGTH', str(len(values))))
        cy.append('}')
    fd, name = tempfile.mkstemp(prefix='template_corpus_', suffix='.test.cy', dir=ROOT / 'cyna-port/src')
    os.close(fd)
    try:
        Path(name).write_text('\n'.join(cy))
        run([os.environ.get('CYNA', 'cyna'), 'test', str(ROOT / 'cyna-port')])
    finally:
        Path(name).unlink(missing_ok=True)
    print(f'Template corpus parity passed: {len(cases) - skipped} components; {skipped} invalid SFC inputs skipped (covered by SFC suite).')


if __name__ == '__main__':
    main()
