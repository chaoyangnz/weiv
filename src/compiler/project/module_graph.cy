// Operation: canonical module identity -> Zig-compatible managed output paths and import mapping.
import { ComponentGraph } from .compiler.project.component_graph;
import { normalize } from .compiler.project.resolve_component_path;
import { relative_output } from .compiler.project.output_paths;
import { hash } from .compiler.backend.browser.compute_scope_id;
import { analyze_module_state_raw, canonical_path } from .ffi.script_backend;
import { dirname } from std.path;
import { append, emit_string } from .compiler.backend.browser.emit.js_module.write_javascript;
import { Span } from .compiler.source;
import std.json;
import { Value } from std.json;
import { ScriptDecodeError } from .compiler.sema.script_json;
import .compiler.sema.script_json as validation;
import std.fs;
import std.mem;

pub struct ModuleEntry {
    pub source_path: string;
    pub output: string;
    pub publisher: string;
    pub component: bool;
}

pub enum ModuleMapError {
    module_not_found;
    absolute_import;
    component_missing;
    path_invalid;
    module_collision;
    module_analysis;
}

struct SourceReference {
    source: string;
    span: Span;
}

fn decode_reference(value: &const Value): SourceReference ! ScriptDecodeError {
    return switch value {
        .object(object) => SourceReference {
            source: try validation.text_field(&object, "source"),
            span: try validation.span(&object, "span_start", "span_end")
        };
        _ => {
            throw ScriptDecodeError.wrong_type;
        }
    };
}

fn hex(value: u64): string {
    const digits = "0123456789abcdef".bytes();
    var out = list<u8>();
    var started = false;
    var i: usize = 16;
    while i > 0 {
        i = i - 1;
        const digit = ((value >> (i * 4)) & 15) as usize;
        if not started and digit == 0 {
            continue;
        }
        started = true;
        out.push(digits[digit]);
    }
    if not started {
        out.push(48);
    }
    return string.from(out.view());
}

pub fn runtime_path(module_path: string, specifier: string): string {
    var name = "index.js";
    if specifier == "weiv:cells" {
        name = "cell.js";
    } else if specifier == "weiv:observable" {
        name = "observable.js";
    } else if specifier == "weiv:router" {
        name = "router.js";
    }
    return relative_output(module_path, $"__weiv_runtime/{name}");
}

fn is_file(path: string): bool {
    const _ = fs.read_file(path) catch (code) {
        return false;
    };
    return true;
}

// Zig resolves managed module specifiers through the filesystem, including
// extensionless barrels and index files, and canonicalizes symlinks.
pub fn resolve_local(importer: string, specifier: string): string ! ModuleMapError {
    const parent = dirname(importer);
    const base = normalize($"{parent}/{specifier}") catch (code) {
        throw ModuleMapError.path_invalid;
    };
    const suffixes: [7]string = ["", ".ts", ".mts", ".js", ".mjs", "/index.ts", "/index.js"];
    var i: usize = 0;
    while i < 7 {
        const suffix = suffixes[i];
        const unresolved = $"{base}{suffix}";
        if is_file(unresolved) {
            const candidate = canonical_path(unresolved) catch (code) {
                throw ModuleMapError.path_invalid;
            };
            if candidate.len() > 0 {
                return candidate;
            }
        }
        i = i + 1;
    }
    throw ModuleMapError.module_not_found;
}

pub fn is_script_module(path: string): bool {
    return mem.ends_with(path.bytes(), ".ts".bytes()) or
    mem.ends_with(path.bytes(), ".mts".bytes()) or
    mem.ends_with(path.bytes(), ".js".bytes()) or
    mem.ends_with(path.bytes(), ".mjs".bytes());
}

fn entry_index(entries: &const List<ModuleEntry>, source_path: string): ?usize {
    var i: usize = 0;
    while i < entries.len() {
        if entries[i].source_path == source_path {
            return i;
        }
        i = i + 1;
    }
    return none;
}

pub fn register(entries: &List<ModuleEntry>, source_path: string): usize ! ModuleMapError {
    const existing = entry_index(entries, source_path);
    if existing is index {
        return index;
    }
    const stem = hex(hash(source_path.bytes(), 0));
    const output = $"__weiv_modules/{stem}.mjs";
    var j: usize = 0;
    while j < entries.len() {
        if entries[j].output == output {
            throw ModuleMapError.module_collision;
        }
        j = j + 1;
    }
    const publisher = $"__weiv_modules/{stem}.publisher.mjs";
    entries.push(ModuleEntry {
        source_path: string.from(source_path.bytes()),
        output: output,
        publisher: publisher,
        component: false
    });
    return entries.len() - 1;
}

pub fn component_output(graph: &const ComponentGraph, path: string): string ! ModuleMapError {
    const node = graph.find_node(path);
    if node is index {
        const module_path = graph.nodes[index].module_path;
        return string.from(module_path.bytes());
    }
    throw ModuleMapError.component_missing;
}

pub fn mapped(entries: &List<ModuleEntry>, graph: &const ComponentGraph, importer_output: string, importer_path: string, specifier: string, original: bool): string ! ModuleMapError {
    const bytes = specifier.bytes();
    if specifier == "weiv:cells" or specifier == "weiv:observable" or specifier == "weiv:router" or specifier == "@weiv/runtime" {
        return runtime_path(importer_output, specifier);
    }
    if mem.starts_with(bytes, "/".bytes()) {
        if not original {
            return specifier;
        }
        throw ModuleMapError.absolute_import;
    }
    if not mem.starts_with(bytes, ".".bytes()) {
        return $"/__weiv_packages/{specifier}";
    }
    if not original {
        return specifier;
    }
    const path = try resolve_local(importer_path, specifier);
    if mem.ends_with(path.bytes(), ".weiv".bytes()) {
        const output = try component_output(graph, path);
        return relative_output(importer_output, output);
    }
    const index = try register(entries, path);
    return relative_output(importer_output, entries[index].output);
}

// Literal import spans come from the AST, so import-like strings and comments
// cannot be mistaken for module specifiers.
pub fn rewrite(code: string, entries: &List<ModuleEntry>, graph: &const ComponentGraph, importer_output: string, importer_path: string, original: bool): string ! ModuleMapError {
    const raw = analyze_module_state_raw(code, importer_path) catch (code) {
        throw ModuleMapError.module_analysis;
    };
    const value = json.parse(raw) catch (code) {
        throw ModuleMapError.module_analysis;
    };
    var references = list<SourceReference>();
    switch value {
        .object(object) => {
            references = validation.record_field<SourceReference>(&object, "sources", decode_reference) catch (code) {
                throw ModuleMapError.module_analysis;
            };
        }
        _ => {
            throw ModuleMapError.module_analysis;
        }
    }
    var out = list<u8>();
    var cursor: usize = 0;
    var i: usize = 0;
    const bytes = code.bytes();
    while i < references.len() {
        const reference = &references[i];
        if reference.span.start < cursor or reference.span.end > bytes.len() {
            throw ModuleMapError.module_analysis;
        }
        append(&out, string.from(bytes[cursor..reference.span.start]));
        const target = try mapped(entries, graph, importer_output, importer_path, reference.source, original);
        emit_string(target, &out);
        cursor = reference.span.end;
        i = i + 1;
    }
    append(&out, string.from(bytes[cursor..]));
    return string.from(out.view());
}

// Computed import targets cannot be resolved inside the managed module graph.
pub fn has_opaque_dynamic_import(code: string, path: string): bool ! ModuleMapError {
    const raw = analyze_module_state_raw(code, path) catch (code) {
        throw ModuleMapError.module_analysis;
    };
    const value = json.parse(raw) catch (code) {
        throw ModuleMapError.module_analysis;
    };
    switch value {
        .object(object) => {
            const flag = object.find("opaque_dynamic_import");
            if flag is index {
                const item = &object.members[index].value;
                switch item {
                    .bool(enabled) => {
                        return enabled;
                    }
                    _ => {
                        return false;
                    }
                }
            }
            const sites = object.find("opaque_dynamic_imports");
            if sites is index {
                switch object.members[index].value {
                    .array(records) => {
                        return records.items.len() > 0;
                    }
                    _ => {
                        return false;
                    }
                }
            }
            return false;
        }
        _ => {
            throw ModuleMapError.module_analysis;
        }
    }
}
