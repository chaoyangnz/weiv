// Operation: conditional render nodes with fixed branches -> boundary lifecycle helpers.
import { RenderDocument } from .compiler.backend.browser.render_tree.tree;
import { EvaluatorPlan, EvaluatorSite } from .compiler.backend.browser.emit.evaluator_plan;
import { JavaScriptError } from .compiler.backend.browser.emit.javascript_errors;
import { append } from .compiler.backend.browser.emit.js_module.write_javascript;
import { emit as emit_call } from .compiler.backend.browser.emit.js_module.emit_evaluator_call;
import { emit_nodes } from .compiler.backend.browser.emit.js_module.emit_dom;
import { suffix } from .compiler.backend.browser.emit.js_module.emit_binding_update;
import { emit as emit_destroy_nodes } from .compiler.backend.browser.emit.js_module.emit_destroy_nodes;

fn validate_branch(tree: &const RenderDocument, roots: &const List<usize>): void ! JavaScriptError {
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
            .slot_outlet(value) => {}
            .component(value) => {}
            .conditional(value) => {}
            .for_loop(value) => {}
            _ => {
                throw JavaScriptError.unsupported_template;
            }
        }
    }
    return;
}

fn static_value(source: []const u8, tree: &const RenderDocument, node_id: usize, name: string): ?string {
    const payload = &tree.nodes[node_id].payload;
    switch payload {
        .element(value) => {
            for attribute in value.attributes {
                if string.from(source[attribute.name.start..attribute.name.end]) == name {
                    if attribute.value is span {
                        return string.from(source[span.start..span.end]);
                    }
                    const present: ?string = "";
                    return present;
                }
            }
        }
        _ => {}
    }
    return none;
}

pub fn emit_fixed_updates(source: []const u8, tree: &const RenderDocument, roots: &const List<usize>, plan: &const EvaluatorPlan, out: &List<u8>, scope_name: string, refs_name: string, indentation: string): void ! JavaScriptError {
    var work = list<usize>();
    var r = roots.len();
    while r > 0 {
        r = r - 1;
        work.push(roots[r]);
    }
    while work.len() > 0 {
        const id = work.pop();
        const payload = &tree.nodes[id].payload;
        switch payload {
            .interpolation(value) => {
                const index = plan.find(id, EvaluatorSite.interpolation, 0);
                if index is none {
                    throw JavaScriptError.evaluator_plan_mismatch;
                }
                const ref = value.ref_id;
                append(out, $"{indentation}updateRegion_text_{ref}(instance, {scope_name}, {refs_name});\n");
            }
            .element(value) => {
                var b: usize = 0;
                while b < value.bind_effects.len() {
                    const effect = &value.bind_effects[b];
                    switch effect {
                        .bind(binding) => {
                            const index = plan.find(id, EvaluatorSite.binding, b);
                            if index is none {
                                throw JavaScriptError.evaluator_plan_mismatch;
                            }
                            const target = string.from(source[binding.name.start..binding.name.end]);
                            const name = suffix(target);
                            const ref = value.ref_id;
                            append(out, $"{indentation}updateRegion_attribute_{ref}_{name}(instance, {scope_name}, {refs_name});\n");
                        }
                        _ => {
                            throw JavaScriptError.evaluator_plan_mismatch;
                        }
                    }
                    b = b + 1;
                }
                var c = value.children.len();
                while c > 0 {
                    c = c - 1;
                    work.push(value.children[c]);
                }
            }
            .text(value) => {}
            .conditional(value) => {
                const ref = value.start_ref_id;
                append(out, $"{indentation}updateRegion_conditional_{ref}(instance, {scope_name}, {refs_name});\n");
            }
            .slot_outlet(value) => {
                const ref = value.handle_ref_id;
                append(out, $"{indentation}updateRegion_slot_{ref}(instance, {scope_name}, {refs_name});\n");
            }
            .component(value) => {
                const ref = value.handle_ref_id;
                append(out, $"{indentation}updateRegion_child_{ref}(instance, {scope_name}, {refs_name});\n");
            }
            .for_loop(value) => {
                const ref = value.start_ref_id;
                append(out, $"{indentation}updateRegion_loop_{ref}(instance, {scope_name}, {refs_name});\n");
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
            .conditional(value) => {
                try validate_branch(tree, &value.consequent);
                try validate_branch(tree, &value.alternate);
                const start = value.start_ref_id;
                const end = value.end_ref_id;
                const state = value.state_ref_id;
                const index = plan.find(id, EvaluatorSite.condition, 0);
                if index is none {
                    throw JavaScriptError.evaluator_plan_mismatch;
                }
                const call = emit_call(&plan.records[index], "scope");
                append(&out, $"function createConditionalFragment_{start}(instance, scope, refs, isConsequent) \{\n  const fragment = document.createDocumentFragment();\n");
                append(&out, $"  fragment.__weiv_namespace = refs[{start}].parentNode?.localName === \"foreignObject\" ? undefined : refs[{start}].parentNode?.namespaceURI;\n  if (isConsequent) \{\n");
                try emit_nodes(source, tree, &value.consequent, scope, plan, &out, 2, "refs", "fragment", "scope");
                append(&out, "  } else {\n");
                try emit_nodes(source, tree, &value.alternate, scope, plan, &out, 2, "refs", "fragment", "scope");
                append(&out, "  }\n  return fragment;\n}\n\n");
                append(&out, $"function destroyConditionalBranch_{start}(instance, refs, wasConsequent) \{\n  if (wasConsequent) \{\n");
                emit_destroy_nodes(tree, &value.consequent, &out, 2, "refs");
                append(&out, "  } else {\n");
                emit_destroy_nodes(tree, &value.alternate, &out, 2, "refs");
                append(&out, "  }\n}\n\n");
                append(&out, $"function updateConditional_{start}(instance, scope, refs) \{\n  const next = Boolean({call});\n");
                append(&out, $"  if (refs[{state}] !== next) \{\n    const previous = refs[{state}];\n    destroyConditionalBranch_{start}(instance, refs, previous === true);\n    refs[{state}] = next;\n    replaceBetween(refs[{start}], refs[{end}], createConditionalFragment_{start}(instance, scope, refs, next));\n  \}\n  if (next) \{\n");
                try emit_fixed_updates(source, tree, &value.consequent, plan, &out, "scope", "refs", "    ");
                append(&out, "  } else {\n");
                try emit_fixed_updates(source, tree, &value.alternate, plan, &out, "scope", "refs", "    ");
                append(&out, "  }\n}\n\n");
            }
            _ => {}
        }
        id = id + 1;
    }
    return string.from(out.view());
}

pub fn updates(tree: &const RenderDocument): string {
    var out = list<u8>();
    var id: usize = 0;
    while id < tree.nodes.len() {
        const payload = &tree.nodes[id].payload;
        switch payload {
            .conditional(value) => {
                const start = value.start_ref_id;
                append(&out, $"function updateRegion_conditional_{start}(instance, scope, refs) \{\n  updateConditional_{start}(instance, scope, refs);\n\}\n");
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
            .conditional(value) => {
                const state = value.state_ref_id;
                append(&out, $"  if (refs[{state}] === true) \{\n  \} else \{\n  \}\n");
            }
            _ => {}
        }
        id = id + 1;
    }
    return string.from(out.view());
}
