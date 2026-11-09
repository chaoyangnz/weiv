// Operation: parent slot provisions -> owner-scoped projected mount helpers.
import { RenderDocument } from .compiler.backend.browser.render_tree.tree;
import { EvaluatorPlan } from .compiler.backend.browser.emit.evaluator_plan;
import { JavaScriptError } from .compiler.backend.browser.emit.javascript_errors;
import { append } from .compiler.backend.browser.emit.js_module.write_javascript;
import { emit_nodes_into } from .compiler.backend.browser.emit.js_module.emit_dom;
import { emit_fixed_updates } from .compiler.backend.browser.emit.js_module.emit_conditionals;
import { emit as emit_destroy_nodes } from .compiler.backend.browser.emit.js_module.emit_destroy_nodes;

fn validate_children(tree: &const RenderDocument, roots: &const List<usize>): void ! JavaScriptError {
    var work = list<usize>();
    for id in roots {
        work.push(id);
    }
    while work.len() > 0 {
        const id = work.pop();
        const payload = &tree.nodes[id].payload;
        switch payload {
            .text(value) => {}
            .interpolation(value) => {}
            .element(value) => {
                for child in value.children {
                    work.push(child);
                }
            }
            .conditional(value) => {}
            .for_loop(value) => {}
            .component(value) => {}
            .slot_outlet(value) => {}
            _ => {
                throw JavaScriptError.unsupported_template;
            }
        }
    }
    return;
}

pub fn emit(source: []const u8, tree: &const RenderDocument, scope: string, plan: &const EvaluatorPlan, selected: usize): string ! JavaScriptError {
    var out = list<u8>();
    var id: usize = selected;
    while id < selected + 1 {
        const payload = &tree.nodes[id].payload;
        switch payload {
            .component(value) => {
                var slot: usize = 0;
                while slot < value.slot_provisions.len() {
                    const provision = &value.slot_provisions[slot];
                    try validate_children(tree, &provision.children);
                    const handle = value.handle_ref_id;
                    append(&out, $"function mountProjectedSlot_{handle}_{slot}(start, end, ownerInstance) \{\n  const instance = \{ refs: [], refresh: () => ownerInstance.refresh(), update: () => ownerInstance.update() \};\n  const refs = instance.refs;\n  const fragment = document.createDocumentFragment();\n  fragment.__weiv_namespace = start.parentNode?.localName === \"foreignObject\" ? undefined : start.parentNode?.namespaceURI;\n");
                    try emit_nodes_into(source, tree, &provision.children, scope, plan, &out, "refs", "fragment", "instance.refresh()");
                    append(&out, "  replaceBetween(start, end, fragment);\n  function update() {\n    const refs = instance.refs;\n    const scope = instance.refresh();\n");
                    try emit_fixed_updates(source, tree, &provision.children, plan, &out, "scope", "refs", "    ");
                    append(&out, "  }\n  function destroy() {\n    const refs = instance.refs;\n");
                    emit_destroy_nodes(tree, &provision.children, &out, 2, "refs");
                    append(&out, "  }\n  update();\n  return { update, destroy, start, end };\n}\n\n");
                    slot = slot + 1;
                }
            }
            _ => {}
        }
        id = id + 1;
    }
    return string.from(out.view());
}
