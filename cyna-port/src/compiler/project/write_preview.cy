// Operation: browser project output -> directly runnable preview directory.
import { ComponentGraph } from .compiler.project.component_graph;
import { ProjectBuild } from .compiler.project.project_build;
import { write_with_runtime, WriteError } from .compiler.project.write_project;
import { append } from .compiler.backend.browser.emit.js_module.write_javascript;
import std.fs;
import std.path;
import { infer as infer_preview_props } from .compiler.project.preview_props;
import { source as preview_server_source } from .compiler.project.preview_server;

pub fn write_preview(graph: &const ComponentGraph, project: &const ProjectBuild, output: string, runtime: string): void ! WriteError {
    try write_with_runtime(project, output, runtime);

    var bundle = list<u8>();
    append(&bundle, $"import * as Root from \"./{project.entry_module}\";\n");
    var i: usize = 0;
    while i < graph.imports.len() {
        const edge = &graph.imports[i];
        if graph.find_node(edge.target_path) is index {
            const module_name = graph.nodes[index].module_path;
            append(&bundle, $"import * as Component_{i} from \"./{module_name}\";\n");
        }
        i = i + 1;
    }
    append(&bundle, "\nexport const components = {\n");
    i = 0;
    while i < graph.imports.len() {
        const edge = &graph.imports[i];
        append(&bundle, $"  \"{edge.local_name}\": Component_{i}");
        if i + 1 < graph.imports.len() {
            append(&bundle, ",");
        }
        append(&bundle, "\n");
        i = i + 1;
    }
    append(&bundle, "};\n\nexport const root = Root;\nexport const cssPath = \"./styles.css\";\n\nexport function mount(target, props = {}) {\n  return Root.mount(target, props);\n}\n");
    fs.write_file($"{output}/bundle.mjs", string.from(bundle.view())) catch (code) {
        throw WriteError.filesystem;
    };

    const main = "import * as WeivApp from \"./bundle.mjs\";\nimport { props as previewProps } from \"./props.mjs\";\n\nconst target = document.getElementById(\"app\");\nconst props = globalThis.__WEIV_PROPS__ ?? previewProps;\n\nif (target) {\n  WeivApp.mount(target, props);\n}\n\nexport * from \"./bundle.mjs\";\nexport default WeivApp;\n";
    fs.write_file($"{output}/main.mjs", main) catch (code) {
        throw WriteError.filesystem;
    };
    const preview_props = infer_preview_props(graph);
    fs.write_file($"{output}/props.mjs", $"export const props = {preview_props};\n") catch (code) {
        throw WriteError.filesystem;
    };

    const filename = path.basename(graph.entry_path);
    var title = filename;
    const bytes = filename.bytes();
    if bytes.len() >= 5 {
        if string.from(bytes[bytes.len() - 5..]) == ".weiv" {
            title = string.from(bytes[..bytes.len() - 5]);
        }
    }
    const html = $"<!doctype html>\n<html lang=\"en\">\n  <head>\n    <meta charset=\"utf-8\" />\n    <meta name=\"viewport\" content=\"width=device-width, initial-scale=1\" />\n    <title>{title}</title>\n    <link rel=\"stylesheet\" href=\"/styles.css\" />\n  </head>\n  <body>\n    <div id=\"app\"></div>\n    <script type=\"module\" src=\"/main.mjs\"></script>\n  </body>\n</html>\n";
    fs.write_file($"{output}/index.html", html) catch (code) {
        throw WriteError.filesystem;
    };
    fs.write_file($"{output}/package.json", "{\n  \"name\": \"weiv-preview\",\n  \"private\": true,\n  \"type\": \"module\",\n  \"scripts\": {\n    \"dev\": \"bun --hot server.ts\",\n    \"start\": \"bun server.ts\"\n  }\n}\n") catch (code) {
        throw WriteError.filesystem;
    };
    const server = preview_server_source();
    fs.write_file($"{output}/server.ts", server) catch (code) {
        throw WriteError.filesystem;
    };
    return;
}
