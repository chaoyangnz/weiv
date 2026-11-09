// Operation: emitted output paths -> Zig-compatible relative import specifiers.
import { normalize } from .compiler.project.resolve_component_path;
import { append } from .compiler.backend.browser.emit.js_module.write_javascript;

fn common_boundary(left: string, right: string): usize {
    const a = left.bytes();
    const b = right.bytes();
    var limit = a.len();
    if b.len() < limit {
        limit = b.len();
    }
    var boundary: usize = 0;
    var i: usize = 0;
    while i < limit and a[i] == b[i] {
        i = i + 1;
        if a[i - 1] == 47 {
            boundary = i;
        }
    }
    return boundary;
}

fn slashes(bytes: []const u8): usize {
    var count: usize = 0;
    for byte in bytes {
        if byte == 47 {
            count = count + 1;
        }
    }
    return count;
}

fn last_slash(bytes: []const u8): usize {
    var index: usize = 0;
    var i: usize = 0;
    while i < bytes.len() {
        if bytes[i] == 47 {
            index = i;
        }
        i = i + 1;
    }
    return index;
}

// Both paths are relative to the emitted output directory.
pub fn relative_output(from: string, to: string): string {
    const from_abs = normalize($"/__weiv_output/{from}") catch (code) {
        return to;
    };
    const to_abs = normalize($"/__weiv_output/{to}") catch (code) {
        return to;
    };
    const from_bytes = from_abs.bytes();
    const to_bytes = to_abs.bytes();
    const slash = last_slash(from_bytes);
    const from_dir = string.from(from_bytes[..slash]);
    const from_prefix = $"{from_dir}/";
    const common = common_boundary(from_prefix, to_abs);
    var out = list<u8>();
    var from_common = common;
    if from_common > from_dir.bytes().len() {
        from_common = from_dir.bytes().len();
    }
    const from_tail = from_dir.bytes()[from_common..];
    var remaining = slashes(from_tail);
    if from_tail.len() > 0 {
        remaining = remaining + 1;
    }
    while remaining > 0 {
        append(&out, "../");
        remaining = remaining - 1;
    }
    if to_bytes.len() > common {
        append(&out, string.from(to_bytes[common..]));
    }
    const text = string.from(out.view());
    if text.bytes().len() > 0 and text.bytes()[0] == 46 {
        return text;
    }
    return $"./{text}";
}
