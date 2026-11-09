import { analyze_raw, take_response, ScriptBackendError } from .ffi.script_backend;
import { Value } from std.json;
import std.json;
import std.mem;

fn analyze_ok(source: string, path: string): string {
    return analyze_raw(source, path) catch (code) {
        panic("Expected backend response");
    };
}

fn decode(response: string): Value {
    return json.parse(response) catch (code) {
        panic("Expected valid JSON");
    };
}

fn bool_field(response: string, key: string): bool {
    const value = decode(response);
    return switch value {
        .object(object) => switch object[key] {
            .bool(flag) => flag;
            _ => {
                panic("Expected Boolean field");
            }
        };
        _ => {
            panic("Expected response object");
        }
    };
}

fn string_field(response: string, key: string): string {
    const value = decode(response);
    return switch value {
        .object(object) => switch object[key] {
            .string(text) => text;
            _ => {
                panic("Expected string field");
            }
        };
        _ => {
            panic("Expected response object");
        }
    };
}

fn array_length(response: string, key: string): usize {
    const value = decode(response);
    return switch value {
        .object(object) => switch object[key] {
            .array(items) => items.len();
            _ => {
                panic("Expected array field");
            }
        };
        _ => {
            panic("Expected response object");
        }
    };
}

fn first_binding_name(response: string): string {
    const value = decode(response);
    return switch value {
        .object(object) => switch object["bindings"] {
            .array(items) => switch items[0] {
                .object(binding) => switch binding["name"] {
                    .string(name) => name;
                    _ => {
                        panic("Expected binding name");
                    }
                };
                _ => {
                    panic("Expected binding object");
                }
            };
            _ => {
                panic("Expected bindings array");
            }
        };
        _ => {
            panic("Expected response object");
        }
    };
}

fn expect_input_error(source: string, path: string): void {
    const response = analyze_raw(source, path) catch (code) {
        assert(code == ScriptBackendError.embedded_nul);
        return;
    };
    assert(false);
}

test "Rust analysis returns valid owned JSON and transpiled JavaScript" {
    const response = analyze_ok("export const answer: number = 42; export interface Props {} export let props: Props;", "component.ts");
    assert(bool_field(response, "ok"));
    assert(string_field(response, "source_path") == "component.ts");
    assert(first_binding_name(response) == "answer");
    assert(array_length(response, "diagnostics") == 0);
    const code = string_field(response, "transpiled_code");
    assert(mem.contains(code.bytes(), "42".bytes()));
    assert(not mem.contains(code.bytes(), ": number".bytes()));
}

test "script syntax errors remain successful transport responses" {
    const response = analyze_ok("const = ;", "broken.ts");
    assert(not bool_field(response, "ok"));
    assert(array_length(response, "diagnostics") > 0);
    assert(array_length(response, "bindings") == 0);
    assert(string_field(response, "transpiled_code") == "");
}

test "empty source is terminated and analyzed normally" {
    const response = analyze_ok("", "empty.ts");
    assert(bool_field(response, "ok"));
    assert(array_length(response, "bindings") == 0);
}

test "UTF-8 input paths identifiers and output survive byte adaptation" {
    const response = analyze_ok("const café: string = \"🌱\";", "组件/café.ts");
    assert(bool_field(response, "ok"));
    assert(string_field(response, "source_path") == "组件/café.ts");
    assert(first_binding_name(response) == "café");
}

test "source path chooses TSX parsing" {
    const response = analyze_ok("export const view = <div/>;", "view.tsx");
    assert(bool_field(response, "ok"));
    assert(first_binding_name(response) == "view");
}

test "embedded source NUL is rejected instead of analyzing a prefix" {
    const bytes: [3]u8 = [97, 0, 98];
    expect_input_error(string.from(bytes[..3]), "source.ts");
}

test "embedded path NUL is rejected instead of selecting a truncated path" {
    const bytes: [3]u8 = [97, 0, 98];
    expect_input_error("const x = 1;", string.from(bytes[..3]));
}

test "null backend output maps to transport failure without copying or freeing it" {
    const response = take_response(0) catch (code) {
        assert(code == ScriptBackendError.backend_failure);
        return;
    };
    assert(false);
}

test "returned JSON stays owned across repeated Rust calls and frees" {
    const first = analyze_ok("const first = 1;", "first.ts");
    var index: usize = 0;
    while index < 64 {
        const next = analyze_ok("const next = 2;", "next.ts");
        assert(first_binding_name(next) == "next");
        index = index + 1;
    }
    assert(first_binding_name(first) == "first");
    assert(string_field(first, "source_path") == "first.ts");
}

test "JSON escaping round trips unusual path characters" {
    const path = "folder/quote\"slash\\line\nfile.ts";
    const response = analyze_ok("const x = 1;", path);
    assert(string_field(response, "source_path") == path);
}
