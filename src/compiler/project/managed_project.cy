// Operation: bundler input manifest -> project artifacts and source/output map.
import { ComponentGraph } from .compiler.project.component_graph;
import { collect } from .compiler.project.collect_component_graph;
import { build } from .compiler.project.build_project;
import { write_with_runtime } from .compiler.project.write_project;
import { append, emit_string } from .compiler.backend.browser.emit.js_module.write_javascript;
import .compiler.sema.script_json as validation;
import { Value } from std.json;
import std.json;
import std.fs;
import std.mem;

pub enum ManagedProjectError {
    invalid_manifest;
    invalid_component;
    build_failure;
    write_failure;
}

fn text_item(value: &const Value): string ! validation.ScriptDecodeError {
    return try validation.text(value);
}

pub fn emit(input: string, output: string, runtime: string): void ! ManagedProjectError {
    const source = fs.read_file(input) catch (code) {
        throw ManagedProjectError.invalid_manifest;
    };
    const value = json.parse(source) catch (code) {
        throw ManagedProjectError.invalid_manifest;
    };
    var root = "";
    var components = list<string>();
    switch value {
        .object(object) => {
            root = validation.text_field(&object, "root") catch (code) {
                throw ManagedProjectError.invalid_manifest;
            };
            components = validation.record_field<string>(&object, "components", text_item) catch (code) {
                throw ManagedProjectError.invalid_manifest;
            };
        }
        _ => {
            throw ManagedProjectError.invalid_manifest;
        }
    }
    if components.len() == 0 {
        throw ManagedProjectError.invalid_manifest;
    }
    var graph = collect(root, components[0]) catch (code) {
        throw ManagedProjectError.invalid_component;
    };
    var i: usize = 1;
    while i < components.len() {
        const next = collect(root, components[i]) catch (code) {
            throw ManagedProjectError.invalid_component;
        };
        for node in &next.nodes {
            if graph.find_node(node.path) is none {
                graph.nodes.push(node);
            }
        }
        for edge in &next.imports {
            var found = false;
            for existing in &graph.imports {
                if existing.importer_path == edge.importer_path and existing.target_path == edge.target_path and existing.local_name == edge.local_name {
                    found = true;
                }
            }
            if not found {
                graph.imports.push(edge);
            }
        }
        i = i + 1;
    }
    const project = build(&graph) catch (code) {
        throw ManagedProjectError.build_failure;
    };
    write_with_runtime(&project, output, runtime) catch (code) {
        throw ManagedProjectError.write_failure;
    };
    var manifest = list<u8>();
    append(&manifest, "{\"modules\":[");
    var count: usize = 0;
    for artifact in &project.modules {
        if not mem.ends_with(artifact.source_path.bytes(), "#publisher".bytes()) {
            if count > 0 {
                append(&manifest, ",");
            }
            append(&manifest, "{\"source\":");
            emit_string(artifact.source_path, &manifest);
            append(&manifest, ",\"output\":");
            emit_string(artifact.module_path, &manifest);
            append(&manifest, ",\"component\":");
            if mem.ends_with(artifact.source_path.bytes(), ".weiv".bytes()) {
                append(&manifest, "true");
            } else {
                append(&manifest, "false");
            }
            append(&manifest, "}");
            count = count + 1;
        }
    }
    append(&manifest, "]}");
    fs.write_file($"{output}/manifest.json", string.from(manifest.view())) catch (code) {
        throw ManagedProjectError.write_failure;
    };
    return;
}
