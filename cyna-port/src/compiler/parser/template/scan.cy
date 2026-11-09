import { Span } from .compiler.source;

pub fn whitespace(byte: u8): bool {
    return byte == 32 or (byte >= 9 and byte <= 13);
}

pub fn starts_with(source: []const u8, at: usize, text: string): bool {
    const bytes = text.bytes();
    if at > source.len() or bytes.len() > source.len() - at {
        return false;
    }
    var i: usize = 0;
    while i < bytes.len() {
        if source[at + i] != bytes[i] {
            return false;
        }
        i = i + 1;
    }
    return true;
}

pub fn equal_spans(source: []const u8, a: Span, b: Span): bool {
    if a.end - a.start != b.end - b.start {
        return false;
    }
    var i: usize = 0;
    while i < a.end - a.start {
        if source[a.start + i] != source[b.start + i] {
            return false;
        }
        i = i + 1;
    }
    return true;
}

pub fn equals(source: []const u8, span: Span, text: string): bool {
    return span.end - span.start == text.bytes().len() and starts_with(source, span.start, text);
}

pub fn trim(source: []const u8, start: usize, end: usize): Span {
    var a = start;
    var b = end;
    while a < b and whitespace(source[a]) {
        a = a + 1;
    }
    while b > a and whitespace(source[b - 1]) {
        b = b - 1;
    }
    return {
        start: a,
        end: b
    };
}

pub fn open_tag_end(source: []const u8, start: usize): ?usize {
    var i = start;
    var quoted = false;
    while i < source.len() {
        if source[i] == 34 {
            quoted = not quoted;
        }
        if source[i] == 62 and not quoted {
            return i;
        }
        i = i + 1;
    }
    return none;
}

pub fn void_tag(source: []const u8, name: Span): bool {
    const names: [14]string = ["area", "base", "br", "col", "embed", "hr", "img", "input", "link", "meta", "param", "source", "track", "wbr"];
    for candidate in names {
        const bytes = candidate.bytes();
        var equal = name.end - name.start == bytes.len();
        var i: usize = 0;
        while equal and i < bytes.len() {
            var byte = source[name.start + i];
            if byte >= 65 and byte <= 90 {
                byte = byte + 32;
            }
            if byte != bytes[i] {
                equal = false;
            }
            i = i + 1;
        }
        if equal {
            return true;
        }
    }
    return false;
}

pub fn find(source: []const u8, bounds: Span, text: string): ?usize {
    var i = bounds.start;
    const length = text.bytes().len();
    while i <= bounds.end and length <= bounds.end - i {
        if starts_with(source, i, text) {
            return i;
        }
        i = i + 1;
    }
    return none;
}
