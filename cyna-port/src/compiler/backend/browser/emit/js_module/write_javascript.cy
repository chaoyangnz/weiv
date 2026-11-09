// Operation: byte-exact JavaScript literals, HTML entity decoding and output primitives.
import { decode } from .compiler.backend.browser.emit.js_module.html_entities;
pub fn append(out: &List<u8>, value: string): void {
    for byte in value.bytes() {
        out.push(byte);
    }
}
pub fn emit_string(value: string, out: &List<u8>): void {
    out.push(34);
    for byte in value.bytes() {
        if byte == 92 {
            append(out, "\\\\");
        } else if byte == 34 {
            append(out, "\\\"");
        } else if byte == 10 {
            append(out, "\\n");
        } else if byte == 13 {
            append(out, "\\r");
        } else if byte == 9 {
            append(out, "\\t");
        } else {
            out.push(byte);
        }
    }
    out.push(34);
}
fn numeric(entity: []const u8): ?u32 {
    if entity.len() < 2 or entity[0] != 35 {
        return none;
    }
    var i: usize = 1;
    var base: u32 = 10;
    if entity.len() > 2 and (entity[1] == 120 or entity[1] == 88) {
        base = 16;
        i = 2;
    }
    if i >= entity.len() {
        return none;
    }
    var negative = false;
    if entity[i] == 43 or entity[i] == 45 {
        negative = entity[i] == 45;
        i = i + 1;
    }
    if i >= entity.len() {
        return none;
    }
    if entity[i] == 95 or entity[entity.len() - 1] == 95 {
        return none;
    }
    var value: u32 = 0;
    while i < entity.len() {
        const byte = entity[i];
        if byte != 95 {
            var digit: u32 = 99;
            if byte >= 48 and byte <= 57 {
                digit = (byte - 48) as u32;
            } else if byte >= 65 and byte <= 90 {
                digit = (byte - 55) as u32;
            } else if byte >= 97 and byte <= 122 {
                digit = (byte - 87) as u32;
            }
            if digit >= base {
                return none;
            }
            if value > (2097151 - digit) / base {
                return none;
            }
            value = value * base + digit;
            if negative and value != 0 {
                return none;
            }
        }
        i = i + 1;
    }
    if value == 0 or value > 1114111 or (value >= 55296 and value <= 57343) {
        value = 65533;
    }
    const present: ?u32 = value;
    return present;
}
fn codepoint(out: &List<u8>, value: u32): void {
    if value < 128 {
        out.push(value as u8);
    } else if value < 2048 {
        out.push((192 | (value >> 6)) as u8);
        out.push((128 | (value & 63)) as u8);
    } else if value < 65536 {
        out.push((224 | (value >> 12)) as u8);
        out.push((128 | ((value >> 6) & 63)) as u8);
        out.push((128 | (value & 63)) as u8);
    } else {
        out.push((240 | (value >> 18)) as u8);
        out.push((128 | ((value >> 12) & 63)) as u8);
        out.push((128 | ((value >> 6) & 63)) as u8);
        out.push((128 | (value & 63)) as u8);
    }
}
pub fn emit_html_string(value: string, out: &List<u8>): void {
    const bytes = value.bytes();
    var decoded = list<u8>();
    var cursor: usize = 0;
    while cursor < bytes.len() {
        var consumed = false;
        if bytes[cursor] == 38 {
            var end = cursor + 1;
            while end < bytes.len() and bytes[end] != 59 {
                end = end + 1;
            }
            if end < bytes.len() and end - cursor <= 40 {
                const entity = string.from(bytes[cursor + 1..end]);
                if decode(entity) is text {
                    append(&decoded, text);
                    cursor = end + 1;
                    consumed = true;
                } else if numeric(entity.bytes()) is scalar {
                    codepoint(&decoded, scalar);
                    cursor = end + 1;
                    consumed = true;
                }
            }
        }
        if not consumed {
            decoded.push(bytes[cursor]);
            cursor = cursor + 1;
        }
    }
    emit_string(string.from(decoded.view()), out);
}
pub fn ref_name(id: usize): string {
    return $"__ref_{id}";
}
pub fn indent(depth: usize, out: &List<u8>): void {
    var i: usize = 0;
    while i < depth {
        append(out, "  ");
        i = i + 1;
    }
}
