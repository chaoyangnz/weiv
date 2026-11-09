// Operation: child component effects and handles -> props, callbacks, updates and cleanup.
import { RenderDocument, RenderComponent } from .compiler.backend.browser.render_tree.tree;
import { EvaluatorPlan, EvaluatorSite } from .compiler.backend.browser.emit.evaluator_plan;
import { JavaScriptError } from .compiler.backend.browser.emit.javascript_errors;
import { append, emit_string } from .compiler.backend.browser.emit.js_module.write_javascript;
import { emit as emit_call } from .compiler.backend.browser.emit.js_module.emit_evaluator_call;

pub fn props(source: []const u8, value: &const RenderComponent, node_id: usize, plan: &const EvaluatorPlan, scope: string): string ! JavaScriptError {
    var out = list<u8>();
    append(&out, "{");
    var i: usize = 0;
    while i < value.bind_effects.len() {
        const effect = &value.bind_effects[i];
        switch effect {
            .bind(binding) => {
                if i > 0 {
                    append(&out, ", ");
                }
                const name = string.from(source[binding.name.start..binding.name.end]);
                emit_string(name, &out);
                append(&out, ": ");
                const index = plan.find(node_id, EvaluatorSite.binding, i);
                if index is none {
                    throw JavaScriptError.evaluator_plan_mismatch;
                }
                append(&out, emit_call(&plan.records[index], scope));
            }
            _ => {
                throw JavaScriptError.evaluator_plan_mismatch;
            }
        }
        i = i + 1;
    }
    append(&out, "}");
    return string.from(out.view());
}

pub fn handlers(source: []const u8, value: &const RenderComponent, node_id: usize, plan: &const EvaluatorPlan, scope: string): string ! JavaScriptError {
    var out = list<u8>();
    append(&out, "{");
    var i: usize = 0;
    while i < value.event_effects.len() {
        const effect = &value.event_effects[i];
        switch effect {
            .event(event) => {
                if i > 0 {
                    append(&out, ", ");
                }
                const name = string.from(source[event.name.start..event.name.end]);
                emit_string(name, &out);
                append(&out, ": (payload) => { const resolved = ");
                const index = plan.find(node_id, EvaluatorSite.handler, i);
                if index is none {
                    throw JavaScriptError.evaluator_plan_mismatch;
                }
                append(&out, emit_call(&plan.records[index], scope));
                append(&out, "; return resolved; }");
            }
            _ => {
                throw JavaScriptError.evaluator_plan_mismatch;
            }
        }
        i = i + 1;
    }
    append(&out, "}");
    return string.from(out.view());
}

pub fn slots(source: []const u8, value: &const RenderComponent, owner: string): string {
    var out = list<u8>();
    append(&out, "{ ");
    var i: usize = 0;
    while i < value.slot_provisions.len() {
        if i > 0 {
            append(&out, ", ");
        }
        const provision = &value.slot_provisions[i];
        if provision.name is span {
            emit_string(string.from(source[span.start..span.end]), &out);
        } else {
            append(&out, "default");
        }
        const handle = value.handle_ref_id;
        append(&out, $": \{ mountIntoBoundary: (start, end) => mountProjectedSlot_{handle}_{i}(start, end, {owner}) \}");
        i = i + 1;
    }
    append(&out, " }");
    return string.from(out.view());
}

pub fn region_update(source: []const u8, tree: &const RenderDocument, plan: &const EvaluatorPlan, id: usize): string ! JavaScriptError {
    var out = list<u8>();
    const payload = &tree.nodes[id].payload;
    switch payload {
        .component(value) => {
            const ref = value.handle_ref_id;
            append(&out, $"function updateRegion_child_{ref}(instance, scope, refs) \{\n  if (!refs[{ref}]) return;\n");
            if value.bind_effects.len() > 0 {
                const object = try props(source, &value, id, plan, "scope");
                append(&out, $"  refs[{ref}].setProps({object});\n");
            }
            if value.event_effects.len() > 0 {
                const object = try handlers(source, &value, id, plan, "scope");
                append(&out, $"  refs[{ref}].setEventHandlers({object});\n");
            }
            if value.slot_provisions.len() > 0 {
                const object = slots(source, &value, "instance");
                append(&out, $"  refs[{ref}].setSlots({object});\n");
            }
            if value.bind_effects.len() > 0 or value.slot_provisions.len() > 0 {
                append(&out, $"  refs[{ref}].update();\n");
            }
            append(&out, "}\n");
        }
        _ => {
            throw JavaScriptError.evaluator_plan_mismatch;
        }
    }
    return string.from(out.view());
}

pub fn destroy(tree: &const RenderDocument, selected: usize): string {
    var out = list<u8>();
    var id: usize = selected;
    while id < selected + 1 {
        const payload = &tree.nodes[id].payload;
        switch payload {
            .component(value) => {
                const ref = value.handle_ref_id;
                append(&out, $"  if (refs[{ref}] && typeof refs[{ref}].destroy === \"function\") \{\n    refs[{ref}].destroy();\n  \}\n  refs[{ref}] = undefined;\n");
            }
            _ => {}
        }
        id = id + 1;
    }
    return string.from(out.view());
}
