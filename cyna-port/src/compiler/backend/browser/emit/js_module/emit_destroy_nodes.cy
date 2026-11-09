// Operation: emit lifecycle cleanup in render-node order.
import { RenderDocument } from .compiler.backend.browser.render_tree.tree;
import { append, indent } from .compiler.backend.browser.emit.js_module.write_javascript;

struct DestroyVisit {
    id: usize;
    depth: usize;
    phase: usize;
}

fn queue_children(children: &const List<usize>, depth: usize, work: &List<DestroyVisit>): void {
    var index = children.len();
    while index > 0 {
        index = index - 1;
        work.push(DestroyVisit {
            id: children[index],
            depth: depth,
            phase: 0
        });
    }
}

pub fn emit(tree: &const RenderDocument, roots: &const List<usize>, out: &List<u8>, depth: usize, refs_name: string): void {
    var work = list<DestroyVisit>();
    queue_children(roots, depth, &work);
    while work.len() > 0 {
        const visit = work.pop();
        const payload = &tree.nodes[visit.id].payload;
        switch payload {
            .element(value) => {
                queue_children(&value.children, visit.depth, &work);
            }
            .conditional(value) => {
                if visit.phase == 0 {
                    indent(visit.depth, out);
                    append(out, $"if ({refs_name}[{value.state_ref_id}] === true) \{\n");
                    work.push(DestroyVisit {
                        id: visit.id,
                        depth: visit.depth,
                        phase: 1
                    });
                    queue_children(&value.consequent, visit.depth + 1, &work);
                } else if visit.phase == 1 {
                    indent(visit.depth, out);
                    append(out, "} else {\n");
                    work.push(DestroyVisit {
                        id: visit.id,
                        depth: visit.depth,
                        phase: 2
                    });
                    queue_children(&value.alternate, visit.depth + 1, &work);
                } else {
                    indent(visit.depth, out);
                    append(out, "}\n");
                }
            }
            .slot_outlet(value) => {
                const handle = value.handle_ref_id;
                if visit.phase == 0 {
                    indent(visit.depth, out);
                    append(out, $"const __destroy_slot_{handle} = {refs_name}[{handle}];\n");
                    indent(visit.depth, out);
                    append(out, $"if (__destroy_slot_{handle} && __destroy_slot_{handle} !== false && typeof __destroy_slot_{handle}.destroy === \"function\") \{\n");
                    indent(visit.depth + 1, out);
                    append(out, $"__destroy_slot_{handle}.destroy();\n");
                    indent(visit.depth, out);
                    append(out, "} else {\n");
                    work.push(DestroyVisit {
                        id: visit.id,
                        depth: visit.depth,
                        phase: 1
                    });
                    queue_children(&value.fallback_children, visit.depth + 1, &work);
                } else {
                    indent(visit.depth, out);
                    append(out, "}\n");
                }
            }
            .component(value) => {
                const handle = value.handle_ref_id;
                indent(visit.depth, out);
                append(out, $"if ({refs_name}[{handle}] && typeof {refs_name}[{handle}].destroy === \"function\") \{\n");
                indent(visit.depth + 1, out);
                append(out, $"{refs_name}[{handle}].destroy();\n");
                indent(visit.depth, out);
                append(out, "}\n");
                indent(visit.depth, out);
                append(out, $"{refs_name}[{handle}] = undefined;\n");
            }
            .for_loop(value) => {
                const state = value.state_ref_id;
                indent(visit.depth, out);
                append(out, $"const __records_{state} = {refs_name}[{state}] ?? [];\n");
                indent(visit.depth, out);
                append(out, $"for (const record of __records_{state}) \{\n");
                indent(visit.depth + 1, out);
                append(out, "if (record.handle && typeof record.handle.destroy === \"function\") {\n");
                indent(visit.depth + 2, out);
                append(out, "record.handle.destroy();\n");
                indent(visit.depth + 1, out);
                append(out, "} else if (typeof record.destroy === \"function\") {\n");
                indent(visit.depth + 2, out);
                append(out, "record.destroy();\n");
                indent(visit.depth + 1, out);
                append(out, "}\n");
                indent(visit.depth, out);
                append(out, "}\n");
            }
            _ => {}
        }
    }
}
