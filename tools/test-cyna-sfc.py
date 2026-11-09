#!/usr/bin/env python3
"""Compare Cyna SFC results with the unchanged Zig parser (no Rust backend needed)."""
import argparse
import os
from pathlib import Path
import re
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
PORT = ROOT / 'cyna-port'


def literal(data):
    # Zig byte-hex escapes preserve the original input bytes.
    return '"' + ''.join(chr(b) if 32 <= b < 127 and b not in (34, 92) else f'\\x{b:02x}' for b in data) + '"'


def cyna_literal(data):
    # Cyna does not use Zig's byte-hex string escapes. Preserve UTF-8 literally.
    text = data.decode('utf-8')
    escapes = {'\\': '\\\\', '"': '\\"', '\n': '\\n', '\r': '\\r', '\t': '\\t'}
    return '"' + ''.join(escapes.get(ch, ch) for ch in text) + '"'


def run(args):
    result = subprocess.run(args, cwd=ROOT, text=True, capture_output=True)
    if result.returncode:
        print(result.stdout, end='')
        print(result.stderr, end='')
        raise SystemExit(result.returncode)
    return result


def main():
    options = argparse.ArgumentParser(description=__doc__)
    options.add_argument('--update-reference-tests', action='store_true',
                         help='save the verified Cyna reference suite for direct cyna test use')
    args = options.parse_args()
    template = '<template></template>'
    script = '<script lang="ts"></script>'
    style = '<style></style>'
    targeted = [
        '', template, script, style, 'text', '<', '<template>',
        '<unknown></unknown>', '<></>', template + '<script',
        template + '<script lang="ts">', template + '<script></script>',
        template + "<script lang='ts'></script>",
        template + '<script lang="js"></script>',
        template + template + script, template + script + script,
        template + script + style + style, template + style + script,
        script + template, template + script + '<other></other>',
        template + script, template + script + style,
        '\t\r\n' + template + '\v\f' + script + ' ',
        '<template>héllo 🌱</template>' + script,
        '<template><template>x</template><template/></template>' + script,
        '<template><template-extra/></template>' + script,
        '<template><template /></template>' + script,
        '<template><template>x</template>' + script,
        '<template>x</template >' + script,
        '< template>x</template>' + script,
        template + '<script  lang="ts" ></script>',
        template + '<script\tlang="ts"></script>',
        template + '<script lang="ts">const x = "<script>";</script>',
        template + script + '<style scoped>p{color:red}</style>',
        template + script + 'trailing',
    ]
    cases = [(f'edge-{i}', s.encode()) for i, s in enumerate(targeted)]
    # Restrict to tracked files so installed packages and build output cannot enter the corpus.
    paths = run(['git', 'ls-files', '*.weiv']).stdout.splitlines()
    cases += [(p, (ROOT / p).read_bytes()) for p in paths]
    zig = ['const std = @import("std");', 'const sfc = @import("src/compiler/parser/sfc.zig");', '''
fn emit(section: sfc.Section, source: []const u8) void {
    const base = @intFromPtr(source.ptr);
    std.debug.print(" {d} {d} {d} {d} {d} {d} {d} {d} {d} {d}", .{
        @intFromPtr(section.tag_name.ptr)-base, @intFromPtr(section.tag_name.ptr)-base+section.tag_name.len,
        @intFromPtr(section.attributes.ptr)-base, @intFromPtr(section.attributes.ptr)-base+section.attributes.len,
        section.open_span.start, section.open_span.end, section.content_span.start, section.content_span.end,
        section.close_span.start, section.close_span.end });
}
''']
    for i, (_, source) in enumerate(cases):
        zig.append(f'''test "case-{i}" {{
    const source = {literal(source)};
    const doc = sfc.parse(source) catch |err| {{
        std.debug.print("\\nORACLE {i} ERROR {{s}}\\n", .{{@errorName(err)}});
        return;
    }};
    std.debug.print("\\nORACLE {i} OK", .{{}});
    emit(doc.template, source); emit(doc.script, source);
    if (doc.style) |style| emit(style, source);
    std.debug.print("\\n", .{{}});
}}
''')
    # Zig module imports must stay inside the root module directory.
    fd, oracle_name = tempfile.mkstemp(prefix='.cyna-sfc-oracle-', suffix='.zig', dir=ROOT)
    os.close(fd)
    cy_fd, cy_name = tempfile.mkstemp(prefix='sfc_parity_', suffix='.test.cy', dir=PORT / 'src')
    os.close(cy_fd)
    try:
        Path(oracle_name).write_text('\n'.join(zig))
        result = run([os.environ.get('ZIG', 'zig'), 'test', oracle_name])
        expected = dict((int(m[0]), m[1]) for m in re.findall(r'ORACLE (\d+) ([^\n]+)', result.stderr))
        assert len(expected) == len(cases), 'Incomplete Zig oracle output'
        cy = ['// Permanent Zig-reference cases. Run directly with: cyna test cyna-port',
              '// Refresh explicitly with: python3 tools/test-cyna-sfc.py --update-reference-tests',
              '// Review expectation changes; normal tests never regenerate them.',
              'import { parse, ParseError } from .compiler.parser.sfc.parse;',
              'import { SfcSection } from .compiler.parser.sfc.ast;',
              '''
fn expect_section(actual: SfcSection, expected: [10]usize): void {
    assert(actual.tag_name.start == expected[0]);
    assert(actual.tag_name.end == expected[1]);
    assert(actual.attributes.start == expected[2]);
    assert(actual.attributes.end == expected[3]);
    assert(actual.open_span.start == expected[4]);
    assert(actual.open_span.end == expected[5]);
    assert(actual.content_span.start == expected[6]);
    assert(actual.content_span.end == expected[7]);
    assert(actual.close_span.start == expected[8]);
    assert(actual.close_span.end == expected[9]);
}
''']
        for i, (label, source) in enumerate(cases):
            outcome = expected[i]
            cy.append(f'test {cyna_literal(label.encode())} {{')
            if outcome.startswith('ERROR '):
                error = re.sub(r'(?<!^)(?=[A-Z])', '_', outcome[6:]).lower()
                cy.append(f'    const doc = parse({cyna_literal(source)}.bytes()) catch (code) {{\n        assert(code == ParseError.{error});\n        return;\n    }};\n    assert(false);')
            else:
                cy.append(f'    const doc = parse({cyna_literal(source)}.bytes()) catch (code) {{ assert(false); return; }};')
                values = list(map(int, outcome[3:].split()))
                assert len(values) in (20, 30)
                for n, section in enumerate(['doc.template', 'doc.script', 'style'][:len(values)//10]):
                    if n == 2:
                        cy.append('    if doc.style is style {')
                    ranges = ', '.join(map(str, values[n*10:(n+1)*10]))
                    cy.append(f'    expect_section({section}, [{ranges}]);')
                    if n == 2:
                        cy.append('    } else { assert(false); }')
                if len(values) == 20:
                    cy.append('    if doc.style is unexpected { assert(false); }')
            cy.append('}')
        Path(cy_name).write_text('\n'.join(cy) + '\n')
        run([os.environ.get('CYNA', 'cyna'), 'check', str(PORT)])
        run([os.environ.get('CYNA', 'cyna'), 'test', str(PORT)])
        if args.update_reference_tests:
            destination = PORT / 'src' / 'sfc_reference.test.cy'
            destination.write_text(Path(cy_name).read_text())
            print(f'Updated {destination.relative_to(ROOT)}')
        print(f'SFC parity passed: {len(cases)} cases ({len(targeted)} targeted, {len(paths)} tracked components).')
    finally:
        Path(oracle_name).unlink(missing_ok=True)
        Path(cy_name).unlink(missing_ok=True)


if __name__ == '__main__':
    main()
