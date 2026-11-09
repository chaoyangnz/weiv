// Operation: static or non-structural render forest -> createDom, with iterative traversal.
import { EvaluatorPlan, EvaluatorSite } from .compiler.backend.browser.emit.evaluator_plan;
import { emit as emit_call } from .compiler.backend.browser.emit.js_module.emit_evaluator_call;
import { RenderDocument, RenderElement } from .compiler.backend.browser.render_tree.tree;
import { JavaScriptError } from .compiler.backend.browser.emit.javascript_errors;
import { append, emit_html_string, emit_string, indent, ref_name } from .compiler.backend.browser.emit.js_module.write_javascript;
import .compiler.backend.browser.emit.js_module.module_fragments as fragments;
import { props as component_props, handlers as component_handlers, slots as component_slots } from .compiler.backend.browser.emit.js_module.emit_components;
struct StaticDomVisit {
    id: usize;
    parent: ?usize;
    finish: bool;
}
pub fn validate_static(tree: &const RenderDocument): void ! JavaScriptError {
    var i: usize = 0;
    while i < tree.nodes.len() {
        const payload = &tree.nodes[i].payload;
        switch payload {
            .text(value) => {}
            .element(value) => {
                try validate_element(&value);
            }
            _ => {
                throw JavaScriptError.unsupported_template;
            }
        }
        i = i + 1;
    }
    return;
}
fn validate_element(value: &const RenderElement): void ! JavaScriptError {
    if value.bind_effects.len() > 0 or value.event_effects.len() > 0 {
        throw JavaScriptError.unsupported_template;
    }
    return;
}
fn create_element(source: []const u8, value: &const RenderElement, parent: string, scope: string, refs_name: string, depth: usize, out: &List<u8>): string {
    const name = ref_name(value.ref_id);
    const tag = string.from(source[value.tag_name.start..value.tag_name.end]);
    indent(depth, out);
    if tag == "svg" {
        append(out, $"const {name} = document.createElementNS(\"http://www.w3.org/2000/svg\", \"svg\");\n");
    } else {
        append(out, $"const {name} = ({parent}.namespaceURI === \"http://www.w3.org/2000/svg\" && {parent}.localName !== \"foreignObject\") || {parent}.__weiv_namespace === \"http://www.w3.org/2000/svg\" ? document.createElementNS(\"http://www.w3.org/2000/svg\", \"{tag}\") : document.createElement(\"{tag}\");\n");
    }
    const id = value.ref_id;
    indent(depth, out);
    append(out, $"{refs_name}[{id}] = {name};\n");
    indent(depth, out);
    append(out, $"{name}.setAttribute(\"data-weiv-scope\", \"{scope}\");\n");
    var a: usize = 0;
    while a < value.attributes.len() {
        const attribute = &value.attributes[a];
        const key = string.from(source[attribute.name.start..attribute.name.end]);
        indent(depth, out);
        if key == "style" {
            append(out, $"{name}.style.cssText = ");
        } else {
            append(out, $"{name}.setAttribute(\"{key}\", ");
        }
        var text = "";
        if attribute.value is span {
            text = string.from(source[span.start..span.end]);
        }
        emit_html_string(text, out);
        if key == "style" {
            append(out, ";\n");
        } else {
            append(out, ");\n");
        }
        a = a + 1;
    }
    return name;
}
fn queue_children(value: &const RenderElement, id: usize, outer: ?usize, work: &List<StaticDomVisit>): void {
    work.push(StaticDomVisit {
        id: id,
        parent: outer,
        finish: true
    });
    var i = value.children.len();
    while i > 0 {
        i = i - 1;
        work.push(StaticDomVisit {
            id: value.children[i],
            parent: value.ref_id,
            finish: false
        });
    }
}
pub fn validate(tree: &const RenderDocument): void ! JavaScriptError {
    var i: usize = 0;
    while i < tree.nodes.len() {
        const payload = &tree.nodes[i].payload;
        switch payload {
            .text(value) => {}.interpolation(value) => {}.element(value) => {}
            .conditional(value) => {}
            .for_loop(value) => {}
            .component(value) => {}
            .slot_outlet(value) => {}
            _ => {
                throw JavaScriptError.unsupported_template;
            }
        }
        i = i + 1;
    }
    return;
}
pub fn emit(source: []const u8, tree: &const RenderDocument, scope: string, plan: &const EvaluatorPlan): string ! JavaScriptError {
    try validate(tree);
    var output = list<u8>();
    append(&output, fragments.create_header());
    try emit_nodes(source, tree, &tree.roots, scope, plan, &output, 1, "refs", "fragment", "instance.refresh()");
    append(&output, fragments.create_footer());
    return string.from(output.view());
}

pub fn emit_nodes_into(source: []const u8, tree: &const RenderDocument, roots: &const List<usize>, scope: string, plan: &const EvaluatorPlan, output: &List<u8>, refs_name: string, root_parent: string, event_scope: string): void ! JavaScriptError {
    try emit_nodes(source, tree, roots, scope, plan, output, 1, refs_name, root_parent, event_scope);
    return;
}

pub fn emit_nodes(source: []const u8, tree: &const RenderDocument, roots: &const List<usize>, scope: string, plan: &const EvaluatorPlan, output: &List<u8>, depth: usize, refs_name: string, root_parent: string, event_scope: string): void ! JavaScriptError {
    var work = list<StaticDomVisit>();
    var i = roots.len();
    while i > 0 {
        i = i - 1;
        work.push(StaticDomVisit {
            id: roots[i],
            parent: none,
            finish: false
        });
    }
    while work.len() > 0 {
        const visit = work.pop();
        var parent = root_parent;
        if visit.parent is ref {
            parent = ref_name(ref);
        }
        const payload = &tree.nodes[visit.id].payload;
        switch payload {
            .text(span) => {
                indent(depth, output);
                append(output, $"{parent}.append(document.createTextNode(");
                emit_html_string(string.from(source[span.start..span.end]), output);
                append(output, "));\n");
            }
            .interpolation(value) => {
                const id = value.ref_id;
                const name = ref_name(id);
                indent(depth, output);
                append(output, $"const {name} = document.createTextNode(\"\");\n");
                indent(depth, output);
                append(output, $"{refs_name}[{id}] = {name};\n");
                indent(depth, output);
                append(output, $"{parent}.append({name});\n");
            }
            .element(value) => {
                if visit.finish {
                    const name = ref_name(value.ref_id);
                    indent(depth, output);
                    append(output, $"{parent}.append({name});\n");
                } else {
                    const name = create_element(source, &value, parent, scope, refs_name, depth, output);
                    try emit_events(source, &value, visit.id, plan, output, event_scope, depth);
                    queue_children(&value, visit.id, visit.parent, &work);
                }
            }
            .conditional(value) => {
                const start = ref_name(value.start_ref_id);
                const end = ref_name(value.end_ref_id);
                const start_id = value.start_ref_id;
                const end_id = value.end_ref_id;
                const state_id = value.state_ref_id;
                indent(depth, output);
                append(output, $"const {start} = document.createComment(\"if:start\");\n");
                indent(depth, output);
                append(output, $"const {end} = document.createComment(\"if:end\");\n");
                indent(depth, output);
                append(output, $"{refs_name}[{start_id}] = {start};\n");
                indent(depth, output);
                append(output, $"{refs_name}[{end_id}] = {end};\n");
                indent(depth, output);
                append(output, $"{refs_name}[{state_id}] = undefined;\n");
                indent(depth, output);
                append(output, $"{parent}.append({start});\n");
                indent(depth, output);
                append(output, $"{parent}.append({end});\n");
            }
            .for_loop(value) => {
                const start = ref_name(value.start_ref_id);
                const end = ref_name(value.end_ref_id);
                const start_id = value.start_ref_id;
                const end_id = value.end_ref_id;
                const state_id = value.state_ref_id;
                indent(depth, output);
                append(output, $"const {start} = document.createComment(\"for:start\");\n");
                indent(depth, output);
                append(output, $"const {end} = document.createComment(\"for:end\");\n");
                indent(depth, output);
                append(output, $"{refs_name}[{start_id}] = {start};\n");
                indent(depth, output);
                append(output, $"{refs_name}[{end_id}] = {end};\n");
                indent(depth, output);
                append(output, $"{refs_name}[{state_id}] = [];\n");
                indent(depth, output);
                append(output, $"{parent}.append({start});\n");
                indent(depth, output);
                append(output, $"{parent}.append({end});\n");
            }
            .component(value) => {
                const start = ref_name(value.start_ref_id);
                const end = ref_name(value.end_ref_id);
                const start_id = value.start_ref_id;
                const end_id = value.end_ref_id;
                const handle = value.handle_ref_id;
                const tag = string.from(source[value.tag_name.start..value.tag_name.end]);
                indent(depth, output);
                append(output, $"const {start} = document.createComment(\"component:start\");\n");
                indent(depth, output);
                append(output, $"const {end} = document.createComment(\"component:end\");\n");
                indent(depth, output);
                append(output, $"{refs_name}[{start_id}] = {start};\n");
                indent(depth, output);
                append(output, $"{refs_name}[{end_id}] = {end};\n");
                indent(depth, output);
                append(output, $"{parent}.append({start});\n");
                indent(depth, output);
                append(output, $"{parent}.append({end});\n");
                var prop_arg = "undefined";
                if value.bind_effects.len() > 0 {
                    prop_arg = $"__props_{handle}";
                    const object = try component_props(source, &value, visit.id, plan, event_scope);
                    indent(depth, output);
                    append(output, $"const {prop_arg} = {object};\n");
                }
                var handler_arg = "undefined";
                if value.event_effects.len() > 0 {
                    handler_arg = $"__handlers_{handle}";
                    const object = try component_handlers(source, &value, visit.id, plan, event_scope);
                    indent(depth, output);
                    append(output, $"const {handler_arg} = {object};\n");
                }
                var slot_arg = "undefined";
                if value.slot_provisions.len() > 0 {
                    slot_arg = $"__slots_{handle}";
                    indent(depth, output);
                    append(output, $"const {slot_arg} = ");
                    append(output, component_slots(source, &value, "instance"));
                    append(output, ";\n");
                }
                indent(depth, output);
                append(output, $"{refs_name}[{handle}] = {tag}.mountIntoBoundary({start}, {end}, {prop_arg}, {handler_arg}, {slot_arg});\n");
            }
            .slot_outlet(value) => {
                const start = ref_name(value.start_ref_id);
                const end = ref_name(value.end_ref_id);
                const start_id = value.start_ref_id;
                const end_id = value.end_ref_id;
                const handle = value.handle_ref_id;
                indent(depth, output);
                append(output, $"const {start} = document.createComment(\"slot:start\");\n");
                indent(depth, output);
                append(output, $"const {end} = document.createComment(\"slot:end\");\n");
                indent(depth, output);
                append(output, $"{refs_name}[{start_id}] = {start};\n");
                indent(depth, output);
                append(output, $"{refs_name}[{end_id}] = {end};\n");
                indent(depth, output);
                append(output, $"{refs_name}[{handle}] = false;\n");
                indent(depth, output);
                append(output, $"{parent}.append({start});\n");
                indent(depth, output);
                append(output, $"{parent}.append({end});\n");
                indent(depth, output);
                append(output, $"const __slot_{handle} = ");
                if value.name is span {
                    append(output, "instance.slots?.[");
                    emit_string(string.from(source[span.start..span.end]), output);
                    append(output, "];\n");
                } else {
                    append(output, "instance.slots?.default;\n");
                }
                indent(depth, output);
                append(output, $"if (__slot_{handle}) \{\n");
                indent(depth + 1, output);
                append(output, $"{refs_name}[{handle}] = __slot_{handle}.mountIntoBoundary({start}, {end});\n");
                indent(depth, output);
                append(output, "} else {\n");
                indent(depth + 1, output);
                append(output, $"replaceBetween({start}, {end}, createSlotFallbackFragment_{handle}(instance, {event_scope}));\n");
                indent(depth, output);
                append(output, "}\n");
            }
            _ => {
                throw JavaScriptError.unsupported_template;
            }
        }
    }
    return;
}

fn emit_events(source: []const u8, value: &const RenderElement, node: usize, plan: &const EvaluatorPlan, output: &List<u8>, event_scope: string, depth: usize): void ! JavaScriptError {
    const name = ref_name(value.ref_id);
    var i: usize = 0;
    while i < value.event_effects.len() {
        const effect = &value.event_effects[i];
        switch effect {
            .event(target) => {
                const event = string.from(source[target.name.start..target.name.end]);
                const index = plan.find(node, EvaluatorSite.handler, i);
                if index is none {
                    throw JavaScriptError.evaluator_plan_mismatch;
                }
                const call = emit_call(&plan.records[index], event_scope);
                indent(depth, output);
                append(output, $"{name}.addEventListener(\"{event}\", (event) => \{\n");
                indent(depth + 1, output);
                append(output, $"const resolved = {call};\n");
                indent(depth + 1, output);
                append(output, "return resolved;\n");
                indent(depth, output);
                append(output, "});\n");
            }
            _ => {
                throw JavaScriptError.evaluator_plan_mismatch;
            }
        }
        i = i + 1;
    }
    return;
}
