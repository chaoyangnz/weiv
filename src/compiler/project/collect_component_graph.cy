// Operation: entry source path -> owned local component source/import graph.
import { ComponentGraph, ComponentNode, ComponentImport } from .compiler.project.component_graph;
import { normalize, component, module_path } from .compiler.project.resolve_component_path;
import { parse as parse_sfc } from .compiler.parser.sfc.parse;
import { analyze_raw, canonical_path } from .ffi.script_backend;
import { decode } from .compiler.sema.decode_script_facts;
import std.fs;
import std.mem;

pub enum GraphError {
    invalid_path;
    missing_source;
    invalid_component;
    script_analysis;
}

pub fn collect(root_dir: string, entry_path: string): ComponentGraph ! GraphError {
    const root = canonical_path(root_dir) catch (code) {
        throw GraphError.invalid_path;
    };
    const entry = canonical_path(entry_path) catch (code) {
        throw GraphError.invalid_path;
    };
    var graph: ComponentGraph = {
        root_dir: root,
        entry_path: entry,
        nodes: list<ComponentNode>(),
        imports: list<ComponentImport>()
    };
    var pending = list<string>();
    pending.push(entry);
    while pending.len() > 0 {
        const path = pending.pop();
        if graph.find_node(path) is index {
            continue;
        }
        const output = module_path(root, path) catch (code) {
            throw GraphError.invalid_path;
        };
        const source = fs.read_file(path) catch (code) {
            throw GraphError.missing_source;
        };
        const sfc = parse_sfc(source.bytes()) catch (code) {
            throw GraphError.invalid_component;
        };
        const bytes = source.bytes();
        const span = sfc.script.content_span;
        const script = string.from(bytes[span.start..span.end]);
        const raw = analyze_raw(script, path) catch (code) {
            throw GraphError.script_analysis;
        };
        const decoded = decode(raw) catch (code) {
            throw GraphError.script_analysis;
        };
        if not decoded.facts.ok {
            throw GraphError.script_analysis;
        }
        graph.nodes.push(ComponentNode {
            path: path,
            source: source,
            module_path: output
        });
        var i: usize = 0;
        while i < decoded.facts.imports.len() {
            const record = &decoded.facts.imports[i];
            if mem.ends_with(record.source.bytes(), ".weiv".bytes()) and record.local_name.bytes().len() > 0 {
                const unresolved = component(path, record.source) catch (code) {
                    throw GraphError.invalid_path;
                };
                const target = canonical_path(unresolved) catch (code) {
                    throw GraphError.invalid_path;
                };
                if target.len() == 0 {
                    throw GraphError.missing_source;
                }
                graph.imports.push(ComponentImport {
                    importer_path: path,
                    target_path: target,
                    source: record.source,
                    local_name: record.local_name
                });
                if graph.find_node(target) is none {
                    pending.push(target);
                }
            }
            i = i + 1;
        }
    }
    return graph;
}
