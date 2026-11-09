// Operation: slot outlet fallback and supplied slot handle -> DOM lifecycle helpers.
import { RenderDocument } from .compiler.backend.browser.render_tree.tree;
import { EvaluatorPlan } from .compiler.backend.browser.emit.evaluator_plan;
import { JavaScriptError } from .compiler.backend.browser.emit.javascript_errors;
import { append, emit_string } from .compiler.backend.browser.emit.js_module.write_javascript;
import { emit_nodes } from .compiler.backend.browser.emit.js_module.emit_dom;
import { emit_fixed_updates } from .compiler.backend.browser.emit.js_module.emit_conditionals;

fn validate_fallback(tree: &const RenderDocument, roots: &const List<usize>): void ! JavaScriptError {
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
            .slot_outlet(value) => {
                try validate_fallback(tree, &value.fallback_children);
                const start = value.start_ref_id;
                const end = value.end_ref_id;
                const handle = value.handle_ref_id;
                append(&out, $"function createSlotFallbackFragment_{handle}(instance, scope) \{\n  const refs = instance.refs;\n  const fragment = document.createDocumentFragment();\n  fragment.__weiv_namespace = refs[{start}].parentNode?.localName === \"foreignObject\" ? undefined : refs[{start}].parentNode?.namespaceURI;\n");
                try emit_nodes(source, tree, &value.fallback_children, scope, plan, &out, 1, "refs", "fragment", "instance.refresh()");
                try emit_fixed_updates(source, tree, &value.fallback_children, plan, &out, "scope", "refs", "  ");
                append(&out, "  return fragment;\n}\n\n");
            }
            _ => {}
        }
        id = id + 1;
    }
    return string.from(out.view());
}

pub fn updates(source: []const u8, tree: &const RenderDocument, plan: &const EvaluatorPlan, selected: ?usize): string ! JavaScriptError {
    var out = list<u8>();
    var id: usize = 0;
    while id < tree.nodes.len() {
        if selected is wanted {
            if id != wanted {
                id = id + 1;
                continue;
            }
        }
        const payload = &tree.nodes[id].payload;
        switch payload {
            .slot_outlet(value) => {
                const start = value.start_ref_id;
                const end = value.end_ref_id;
                const handle = value.handle_ref_id;
                append(&out, $"function updateRegion_slot_{handle}(instance, scope, refs) \{\n  const __next_slot_{handle} = ");
                if value.name is span {
                    append(&out, "instance.slots?.[");
                    emit_string(string.from(source[span.start..span.end]), &out);
                    append(&out, "];\n");
                } else {
                    append(&out, "instance.slots?.default;\n");
                }
                append(&out, $"  const __current_slot_{handle} = refs[{handle}];\n  if (__next_slot_{handle}) \{\n    if (__current_slot_{handle} && __current_slot_{handle} !== false) \{\n      __current_slot_{handle}.update();\n    \} else \{\n      refs[{handle}] = __next_slot_{handle}.mountIntoBoundary(refs[{start}], refs[{end}]);\n    \}\n  \} else \{\n    if (__current_slot_{handle} !== false) \{\n      if (__current_slot_{handle} && typeof __current_slot_{handle}.destroy === \"function\") \{ __current_slot_{handle}.destroy(); \}\n      refs[{handle}] = false;\n      replaceBetween(refs[{start}], refs[{end}], createSlotFallbackFragment_{handle}(instance, scope));\n    \}\n");
                try emit_fixed_updates(source, tree, &value.fallback_children, plan, &out, "scope", "refs", "    ");
                append(&out, "  }\n}\n");
            }
            _ => {}
        }
        id = id + 1;
    }
    return string.from(out.view());
}

pub fn destroy(tree: &const RenderDocument, selected: usize): string {
    var out = list<u8>();
    var id: usize = selected;
    while id < selected + 1 {
        const payload = &tree.nodes[id].payload;
        switch payload {
            .slot_outlet(value) => {
                const handle = value.handle_ref_id;
                append(&out, $"  const __destroy_slot_{handle} = refs[{handle}];\n  if (__destroy_slot_{handle} && __destroy_slot_{handle} !== false && typeof __destroy_slot_{handle}.destroy === \"function\") \{\n    __destroy_slot_{handle}.destroy();\n  \} else \{\n  \}\n");
            }
            _ => {}
        }
        id = id + 1;
    }
    return string.from(out.view());
}
