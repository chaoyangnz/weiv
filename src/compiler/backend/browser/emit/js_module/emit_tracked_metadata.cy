// Operation: owned region graph -> reference JavaScript metadata export.
import { RegionGraph } from .compiler.backend.browser.region_graph;
import { kind_label } from .compiler.backend.browser.tracked_roots;
import { append, emit_string } from .compiler.backend.browser.emit.js_module.write_javascript;
pub fn emit(graph: &const RegionGraph): string {
    var out = list<u8>();
    append(&out, "export const trackedStateGraph = { roots: [");
    var i: usize = 0;
    while i < graph.table.roots.len() {
        const root = &graph.table.roots[i];
        if i > 0 {
            append(&out, ", ");
        }
        const id = root.id;
        append(&out, "{ rootId: ");
        append(&out, $"{id}, bindingName: ");
        emit_string(root.binding_name, &out);
        append(&out, ", kind: \"");
        append(&out, kind_label(root.kind));
        append(&out, "\" }");
        i = i + 1;
    }
    append(&out, "], paths: [");
    i = 0;
    while i < graph.table.paths.len() {
        const path = &graph.table.paths[i];
        if i > 0 {
            append(&out, ", ");
        }
        const id = path.id;
        const root = path.root_id;
        append(&out, "{ pathId: ");
        append(&out, $"{id}, rootId: {root}, path: ");
        emit_string(path.path, &out);
        append(&out, ", parentPathId: ");
        if path.parent_path_id is parent {
            append(&out, $"{parent}");
        } else {
            append(&out, "null");
        }
        append(&out, " }");
        i = i + 1;
    }
    append(&out, "], regions: [");
    i = 0;
    var written = false;
    while i < graph.regions.len() {
        const region = &graph.regions[i];
        if region.tracked_path_ids.len() > 0 {
            if written {
                append(&out, ", ");
            }
            const id = region.id;
            append(&out, "{ regionId: ");
            append(&out, $"{id}, trackedPathIds: [");
            var p: usize = 0;
            while p < region.tracked_path_ids.len() {
                if p > 0 {
                    append(&out, ", ");
                }
                const value = region.tracked_path_ids[p];
                append(&out, $"{value}");
                p = p + 1;
            }
            append(&out, "] }");
            written = true;
        }
        i = i + 1;
    }
    append(&out, "] };");
    out.push(10);
    return string.from(out.view());
}
