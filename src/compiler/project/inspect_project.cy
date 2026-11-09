// Operation: project graph and emitted artifacts -> deterministic JSON inventory.
import { ComponentGraph } from .compiler.project.component_graph;
import { ProjectBuild } from .compiler.project.project_build;
import { append } from .compiler.backend.browser.emit.js_module.write_javascript;

fn json_string(value: string, out: &List<u8>): void {
    const hex = "0123456789abcdef".bytes();
    out.push(34);
    for byte in value.bytes() {
        if byte == 34 or byte == 92 {
            out.push(92);
            out.push(byte);
        } else if byte < 32 {
            append(out, "\\u00");
            out.push(hex[(byte / 16) as usize]);
            out.push(hex[(byte % 16) as usize]);
        } else {
            out.push(byte);
        }
    }
    out.push(34);
}

pub fn format(graph: &const ComponentGraph, project: &const ProjectBuild): string {
    var out = list<u8>();
    append(&out, "{\"entry\":");
    json_string(project.entry_module, &out);
    append(&out, ",\"components\":[");
    var i: usize = 0;
    while i < graph.nodes.len() {
        if i > 0 {
            append(&out, ",");
        }
        const node = &graph.nodes[i];
        append(&out, "{\"source\":");
        json_string(node.path, &out);
        append(&out, ",\"output\":");
        json_string(node.module_path, &out);
        append(&out, "}");
        i = i + 1;
    }
    append(&out, "],\"componentImports\":[");
    i = 0;
    while i < graph.imports.len() {
        if i > 0 {
            append(&out, ",");
        }
        const edge = &graph.imports[i];
        append(&out, "{\"importer\":");
        json_string(edge.importer_path, &out);
        append(&out, ",\"target\":");
        json_string(edge.target_path, &out);
        append(&out, ",\"specifier\":");
        json_string(edge.source, &out);
        append(&out, ",\"binding\":");
        json_string(edge.local_name, &out);
        append(&out, "}");
        i = i + 1;
    }
    append(&out, "],\"modules\":[");
    i = 0;
    while i < project.modules.len() {
        if i > 0 {
            append(&out, ",");
        }
        const artifact = &project.modules[i];
        append(&out, "{\"source\":");
        json_string(artifact.source_path, &out);
        append(&out, ",\"output\":");
        json_string(artifact.module_path, &out);
        const code_bytes = artifact.code.bytes().len();
        const css_bytes = artifact.css.bytes().len();
        append(&out, $",\"codeBytes\":{code_bytes},\"cssBytes\":{css_bytes}");
        append(&out, "}");
        i = i + 1;
    }
    const stylesheet_bytes = project.stylesheet.bytes().len();
    append(&out, $"],\"stylesheetBytes\":{stylesheet_bytes}");
    append(&out, "}");
    return string.from(out.view());
}
