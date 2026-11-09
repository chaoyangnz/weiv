// Operation: entry component's Props interface -> preview-safe JavaScript defaults.
import { ComponentGraph } from .compiler.project.component_graph;
import { parse as parse_sfc } from .compiler.parser.sfc.parse;
import { analyze_raw } from .ffi.script_backend;
import { decode } from .compiler.sema.decode_script_facts;
import { append } from .compiler.backend.browser.emit.js_module.write_javascript;
import std.mem;

fn whitespace(byte: u8): bool {
    return byte == 32 or byte == 9 or byte == 10 or byte == 13;
}

fn trim(value: []const u8): []const u8 {
    var start: usize = 0;
    var end = value.len();
    while start < end and whitespace(value[start]) {
        start = start + 1;
    }
    while end > start and whitespace(value[end - 1]) {
        end = end - 1;
    }
    return value[start..end];
}

fn default_for(value: []const u8): ?string {
    if mem.contains(value, "[]".bytes()) or mem.contains(value, "Array<".bytes()) {
        return "[]";
    }
    if mem.contains(value, "string".bytes()) {
        return "\"Preview\"";
    }
    if mem.contains(value, "number".bytes()) or mem.contains(value, "bigint".bytes()) {
        return "0";
    }
    if mem.contains(value, "boolean".bytes()) {
        return "false";
    }
    if mem.starts_with(value, "{".bytes()) {
        return "{}";
    }
    return none;
}

fn interface_body(script: []const u8, type_name: string): ?string {
    const needle = $"interface {type_name}";
    const location = mem.index_of(script, needle.bytes());
    var cursor: usize = 0;
    if location is index {
        cursor = index;
    } else {
        return none;
    }
    while cursor < script.len() and script[cursor] != 123 {
        cursor = cursor + 1;
    }
    if cursor == script.len() {
        return none;
    }
    const start = cursor + 1;
    var depth: usize = 1;
    cursor = start;
    while cursor < script.len() {
        if script[cursor] == 123 {
            depth = depth + 1;
        } else if script[cursor] == 125 {
            depth = depth - 1;
            if depth == 0 {
                return string.from(script[start..cursor]);
            }
        }
        cursor = cursor + 1;
    }
    return none;
}

fn defaults(body: []const u8): string {
    var out = list<u8>();
    append(&out, "{ ");
    var count: usize = 0;
    var start: usize = 0;
    var cursor: usize = 0;
    while cursor <= body.len() {
        if cursor == body.len() or body[cursor] == 59 or body[cursor] == 10 {
            const part = trim(body[start..cursor]);
            if part.len() > 0 and not mem.contains(part, "(".bytes()) {
                const colon = mem.index_of(part, ":".bytes());
                if colon is index {
                    var name = trim(part[..index]);
                    const type_name = trim(part[index + 1..]);
                    if name.len() > 0 and name[name.len() - 1] == 63 {
                        name = name[..name.len() - 1];
                    }
                    if name.len() > 0 and type_name.len() > 0 {
                        if default_for(type_name) is value {
                            if count > 0 {
                                append(&out, ", ");
                            }
                            append(&out, string.from(name));
                            append(&out, ": ");
                            append(&out, value);
                            count = count + 1;
                        }
                    }
                }
            }
            start = cursor + 1;
        }
        cursor = cursor + 1;
    }
    if count == 0 {
        return "{}";
    }
    append(&out, " }");
    return string.from(out.view());
}

pub fn infer(graph: &const ComponentGraph): string {
    if graph.find_node(graph.entry_path) is index {
        const source = graph.nodes[index].source;
        const sfc = parse_sfc(source.bytes()) catch (code) {
            return "{}";
        };
        const span = sfc.script.content_span;
        const script = source.bytes()[span.start..span.end];
        const raw = analyze_raw(string.from(script), graph.entry_path) catch (code) {
            return "{}";
        };
        const decoded = decode(raw) catch (code) {
            return "{}";
        };
        if decoded.facts.props is props {
            if props.props_type_name is type_name {
                if interface_body(script, type_name) is body {
                    return defaults(body.bytes());
                }
            }
        }
    }
    return "{}";
}
