// Operation: source bytes -> SFC model; source ownership stays with the caller.
import { Span } from .compiler.source;
import { SfcSection, SfcDocument } from .compiler.parser.sfc.ast;

pub enum ParseError {
    missing_template;
    missing_script;
    duplicate_template;
    duplicate_script;
    duplicate_style;
    unknown_top_level_section;
    invalid_script_attributes;
    invalid_section_order;
    unterminated_open_tag;
    unterminated_close_tag;
}

fn whitespace(byte: u8): bool {
    return byte == 32 or (byte >= 9 and byte <= 13);
}

fn equal_at(source: []const u8, at: usize, text: []const u8): bool {
    if at > source.len() or text.len() > source.len() - at {
        return false;
    }
    var i: usize = 0;
    while i < text.len() {
        if source[at + i] != text[i] {
            return false;
        }
        i = i + 1;
    }
    return true;
}

fn span_equal(source: []const u8, span: Span, text: string): bool {
    return span.end - span.start == text.bytes().len() and equal_at(source, span.start, text.bytes());
}

fn find_byte(source: []const u8, start: usize, byte: u8): ?usize {
    var i = start;
    while i < source.len() {
        if source[i] == byte {
            return i;
        }
        i = i + 1;
    }
    return none;
}

fn trim(source: []const u8, start: usize, end: usize): Span {
    var first = start;
    var last = end;
    while first < last and whitespace(source[first]) {
        first = first + 1;
    }
    while last > first and whitespace(source[last - 1]) {
        last = last - 1;
    }
    return {
        start: first,
        end: last
    };
}

fn boundary(source: []const u8, index: usize): bool {
    return index < source.len() and (whitespace(source[index]) or source[index] == 62 or source[index] == 47);
}

fn matches(source: []const u8, index: usize, name: Span, closing: bool): bool {
    var offset: usize = 1;
    if closing {
        if index + 1 >= source.len() or source[index + 1] != 47 {
            return false;
        }
        offset = 2;
    }
    var i: usize = 0;
    const length = name.end - name.start;
    if index + offset + length > source.len() {
        return false;
    }
    while i < length {
        if source[index + offset + i] != source[name.start + i] {
            return false;
        }
        i = i + 1;
    }
    return boundary(source, index + offset + length);
}

fn matching_close(source: []const u8, start: usize, name: Span): ?usize {
    var depth: usize = 1;
    var pos = start;
    while pos < source.len() {
        const next = find_byte(source, pos, 60);
        if next is none {
            return none;
        }
        pos = next;
        if matches(source, pos, name, false) {
            const gt = find_byte(source, pos, 62);
            if gt is none {
                return none;
            }
            if gt > pos and source[gt - 1] != 47 {
                depth = depth + 1;
            }
            pos = gt + 1;
        } else if matches(source, pos, name, true) {
            if depth == 1 {
                return pos;
            }
            depth = depth - 1;
            const gt = find_byte(source, pos, 62);
            if gt is none {
                return none;
            }
            pos = gt + 1;
        } else {
            pos = pos + 1;
        }
    }
    return none;
}

fn parse_section(source: []const u8, start: usize): SfcSection ! ParseError {
    const gt = find_byte(source, start, 62);
    if gt is none {
        throw ParseError.unterminated_open_tag;
    }
    const inner = trim(source, start + 1, gt);
    var name_end = inner.start;
    // Preserve Zig's literal-space tokenization, including its attribute offsets.
    while name_end < inner.end and source[name_end] != 32 {
        name_end = name_end + 1;
    }
    if name_end == inner.start {
        throw ParseError.unknown_top_level_section;
    }
    const name: Span = {
        start: inner.start,
        end: name_end
    };
    const attributes = trim(source, start + 1 + name.end - name.start, gt);
    const close = matching_close(source, gt + 1, name);
    if close is none {
        throw ParseError.unterminated_close_tag;
    }
    return {
        tag_name: name,
        attributes: attributes,
        open_span: {
            start: start,
            end: gt + 1
        },
        content_span: {
            start: gt + 1,
            end: close
        },
        close_span: {
            start: close,
            end: close + 2 + name.end - name.start + 1
        }
    };
}

pub fn parse(source: []const u8): SfcDocument ! ParseError {
    var index: usize = 0;
    var template: ?SfcSection = none;
    var script: ?SfcSection = none;
    var style: ?SfcSection = none;
    var order: u8 = 0;
    while index < source.len() and whitespace(source[index]) {
        index = index + 1;
    }
    while index < source.len() {
        if source[index] != 60 {
            throw ParseError.unknown_top_level_section;
        }
        const section = try parse_section(source, index);
        index = section.close_span.end;
        if span_equal(source, section.tag_name, "template") {
            if template != none {
                throw ParseError.duplicate_template;
            }
            if order != 0 {
                throw ParseError.invalid_section_order;
            }
            template = section;
            order = 1;
        } else if span_equal(source, section.tag_name, "script") {
            if script != none {
                throw ParseError.duplicate_script;
            }
            if order > 1 {
                throw ParseError.invalid_section_order;
            }
            if template is none {
                throw ParseError.invalid_section_order;
            }
            if not span_equal(source, section.attributes, "lang=\"ts\"") {
                throw ParseError.invalid_script_attributes;
            }
            script = section;
            order = 2;
        } else if span_equal(source, section.tag_name, "style") {
            if style != none {
                throw ParseError.duplicate_style;
            }
            if order > 2 {
                throw ParseError.invalid_section_order;
            }
            if script is none {
                throw ParseError.invalid_section_order;
            }
            style = section;
            order = 3;
        } else {
            throw ParseError.unknown_top_level_section;
        }
        while index < source.len() and whitespace(source[index]) {
            index = index + 1;
        }
    }
    if template is none {
        throw ParseError.missing_template;
    }
    if script is none {
        throw ParseError.missing_script;
    }
    return {
        template: template,
        script: script,
        style: style
    };
}
