// Operation: optional component stylesheet -> scoped CSS artifact; reference-compatible scanner.
import { ComponentUnit } from .compiler.component_unit;
import { Span } from .compiler.source;
import { CompilationDiagnostic, CompilationStage, SourceOrigin } from .compiler.diagnostics;
import { compute } from .compiler.backend.browser.compute_scope_id;

pub enum CssError {
    unterminated_rule;
}
struct Frame {
    cursor: usize;
    end: usize;
    close: bool;
}
fn write(out: &List<u8>, text: []const u8): void {
    for byte in text {
        out.push(byte);
    }
}
fn whitespace(byte: u8): bool {
    return byte == 32 or (byte >= 9 and byte <= 13);
}
fn starts(bytes: []const u8, start: usize, end: usize, text: string): bool {
    const expected = text.bytes();
    if expected.len() > end - start {
        return false;
    }
    var i: usize = 0;
    while i < expected.len() {
        if bytes[start + i] != expected[i] {
            return false;
        }
        i = i + 1;
    }
    return true;
}
fn trim(bytes: []const u8, start: usize, end: usize): Span {
    var left = start;
    var right = end;
    while left < right and whitespace(bytes[left]) {
        left = left + 1;
    }
    while right > left and whitespace(bytes[right - 1]) {
        right = right - 1;
    }
    return {
        start: left,
        end: right
    };
}
fn global_contents(bytes: []const u8, part: Span): ?Span {
    if not starts(bytes, part.start, part.end, ":global(") or part.end - part.start <= 8 or bytes[part.end - 1] != 41 {
        return none;
    }
    var depth: usize = 1;
    var i = part.start + 8;
    while i + 1 < part.end {
        if bytes[i] == 40 {
            depth = depth + 1;
        } else if bytes[i] == 41 {
            depth = depth - 1;
            if depth == 0 {
                return none;
            }
        }
        i = i + 1;
    }
    if depth != 1 {
        return none;
    }
    const result = trim(bytes, part.start + 8, part.end - 1);
    if result.start == result.end {
        return none;
    }
    const present: ?Span = result;
    return present;
}
fn type_start(byte: u8): bool {
    return (byte >= 65 and byte <= 90) or (byte >= 97 and byte <= 122) or byte == 95 or byte == 45;
}
fn type_continue(byte: u8): bool {
    return type_start(byte) or (byte >= 48 and byte <= 57);
}
fn root_selector(out: &List<u8>, bytes: []const u8, part: Span, scope: string): void {
    var prefix = part.start;
    if bytes[prefix] == 42 {
        prefix = prefix + 1;
    } else if type_start(bytes[prefix]) {
        prefix = prefix + 1;
        while prefix < part.end and type_continue(bytes[prefix]) {
            prefix = prefix + 1;
        }
    }
    write(out, bytes[part.start..prefix]);
    write(out, scope.bytes());
    write(out, bytes[prefix..part.end]);
}
fn selectors(out: &List<u8>, bytes: []const u8, range: Span, scope: string): void {
    var start = range.start;
    var i = range.start;
    var parens: usize = 0;
    var brackets: usize = 0;
    var emitted = false;
    while i <= range.end {
        const at_end = i == range.end;
        if not at_end {
            if bytes[i] == 40 {
                parens = parens + 1;
            } else if bytes[i] == 41 {
                if parens > 0 {
                    parens = parens - 1;
                }
            } else if bytes[i] == 91 {
                brackets = brackets + 1;
            } else if bytes[i] == 93 {
                if brackets > 0 {
                    brackets = brackets - 1;
                }
            }
        }
        if at_end or (bytes[i] == 44 and parens == 0 and brackets == 0) {
            const part = trim(bytes, start, i);
            if part.end > part.start {
                if emitted {
                    write(out, ", ".bytes());
                }
                if global_contents(bytes, part) is global {
                    write(out, bytes[global.start..global.end]);
                } else {
                    root_selector(out, bytes, part, scope);
                    write(out, ", ".bytes());
                    write(out, scope.bytes());
                    out.push(32);
                    write(out, bytes[part.start..part.end]);
                }
                emitted = true;
            }
            start = i + 1;
        }
        i = i + 1;
    }
}
// mode 0: at-rule header, mode 1: qualified selector, mode 2: matching block.
fn boundary(bytes: []const u8, start: usize, end: usize, mode: u8): usize ! CssError {
    var i = start;
    var parens: usize = 0;
    var brackets: usize = 0;
    var depth: usize = 0;
    var quote: ?u8 = none;
    while i < end {
        const byte = bytes[i];
        if quote is delimiter {
            if byte == 92 and i + 1 < end {
                i = i + 2;
                continue;
            }
            if byte == delimiter {
                quote = none;
            }
        } else if byte == 34 or byte == 39 {
            quote = byte;
        } else if mode == 2 {
            if byte == 123 {
                depth = depth + 1;
            } else if byte == 125 {
                if depth == 0 {
                    throw CssError.unterminated_rule;
                }
                depth = depth - 1;
                if depth == 0 {
                    return i;
                }
            }
        } else {
            if byte == 40 {
                parens = parens + 1;
            } else if byte == 41 {
                if parens > 0 {
                    parens = parens - 1;
                }
            } else if mode == 1 and byte == 91 {
                brackets = brackets + 1;
            } else if mode == 1 and byte == 93 {
                if brackets > 0 {
                    brackets = brackets - 1;
                }
            } else if parens == 0 and brackets == 0 and (byte == 123 or (mode == 0 and byte == 59)) {
                return i;
            }
        }
        i = i + 1;
    }
    throw CssError.unterminated_rule;
}
pub fn rewrite(input: []const u8, scope: string): string ! CssError {
    var output = list<u8>();
    var work = list<Frame>();
    work.push(Frame {
        cursor: 0,
        end: input.len(),
        close: false
    });
    while work.len() > 0 {
        var frame = work.pop();
        var active = true;
        while active and frame.cursor < frame.end {
            const start = frame.cursor;
            if whitespace(input[start]) {
                output.push(input[start]);
                frame.cursor = frame.cursor + 1;
            } else if starts(input, start, frame.end, "/*") {
                var end = start + 2;
                var found = false;
                while end + 1 < frame.end and not found {
                    if input[end] == 42 and input[end + 1] == 47 {
                        end = end + 2;
                        found = true;
                    } else {
                        end = end + 1;
                    }
                }
                if not found {
                    end = frame.end;
                }
                write(&output, input[start..end]);
                frame.cursor = end;
            } else if input[start] == 64 {
                const header = try boundary(input, start, frame.end, 0);
                write(&output, input[start..header + 1]);
                if input[header] == 59 {
                    frame.cursor = header + 1;
                } else {
                    const end = try boundary(input, header, frame.end, 2);
                    const name = trim(input, start, header);
                    const recurse = starts(input, name.start, name.end, "@media") or starts(input, name.start, name.end, "@supports") or starts(input, name.start, name.end, "@layer");
                    if recurse {
                        work.push(Frame {
                            cursor: end + 1,
                            end: frame.end,
                            close: frame.close
                        });
                        work.push(Frame {
                            cursor: header + 1,
                            end: end,
                            close: true
                        });
                        active = false;
                    } else {
                        write(&output, input[header + 1..end + 1]);
                        frame.cursor = end + 1;
                    }
                }
            } else {
                const open = try boundary(input, start, frame.end, 1);
                const end = try boundary(input, open, frame.end, 2);
                selectors(&output, input, trim(input, start, open), scope);
                write(&output, " {".bytes());
                write(&output, input[open + 1..end + 1]);
                frame.cursor = end + 1;
            }
        }
        if active and frame.close {
            output.push(125);
        }
    }
    return string.from(output.view());
}
pub fn emit(unit: &const ComponentUnit): string ! CssError {
    if unit.sfc_document.style is style {
        const id = compute(unit.source_path);
        const selector = $"[data-weiv-scope=\"{id}\"]";
        const bytes = unit.source.bytes();
        return try rewrite(bytes[style.content_span.start..style.content_span.end], selector);
    }
    return "";
}
pub fn append_diagnostics(unit: &const ComponentUnit, diagnostics: &List<CompilationDiagnostic>): void {
    const output = emit(unit) catch (code) {
        if unit.sfc_document.style is style {
            var end = style.content_span.end;
            if end <= style.content_span.start {
                end = style.content_span.start + 1;
                if end > unit.source.bytes().len() {
                    end = unit.source.bytes().len();
                }
            }
            diagnostics.push(CompilationDiagnostic {
                stage: CompilationStage.emit,
                origin: SourceOrigin.file,
                severity: "error",
                code: "style.unterminated_rule",
                message: "Unterminated scoped style rule",
                span: Span {
                    start: style.content_span.start,
                    end: end
                },
                fatal: true
            });
        }
        return;
    };
}
