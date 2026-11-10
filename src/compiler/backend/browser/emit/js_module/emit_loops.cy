// Operation: keyed generic loops over fixed DOM body nodes -> lifecycle helpers.
import { RenderDocument, RenderForLoop, RenderComponent } from .compiler.backend.browser.render_tree.tree;
import { EvaluatorPlan, EvaluatorSite } from .compiler.backend.browser.emit.evaluator_plan;
import { JavaScriptError } from .compiler.backend.browser.emit.javascript_errors;
import { append, emit_string } from .compiler.backend.browser.emit.js_module.write_javascript;
import { emit as emit_call } from .compiler.backend.browser.emit.js_module.emit_evaluator_call;
import { emit_nodes_into } from .compiler.backend.browser.emit.js_module.emit_dom;
import { emit_fixed_updates } from .compiler.backend.browser.emit.js_module.emit_conditionals;
import { emit as emit_destroy_nodes } from .compiler.backend.browser.emit.js_module.emit_destroy_nodes;
import { props as component_props, handlers as component_handlers, slots as component_slots } from .compiler.backend.browser.emit.js_module.emit_components;

fn emit_component_entry(source: []const u8, value: &const RenderForLoop, component: &const RenderComponent, child_id: usize, plan: &const EvaluatorPlan, iterable: string, out: &List<u8>): void ! JavaScriptError {
    const start = value.start_ref_id;
    const end = value.end_ref_id;
    const state = value.state_ref_id;
    const item = string.from(source[value.item_name.start..value.item_name.end]);
    const tag = string.from(source[component.tag_name.start..component.tag_name.end]);
    const has_props = component.bind_effects.len() > 0;
    const has_handlers = component.event_effects.len() > 0;
    const has_slots = component.slot_provisions.len() > 0;
    append(out, $"function createForComponentEntry_{start}(instance, scope, item, reference) \{\n  const parent = reference.parentNode;\n  const start = document.createComment(\"for:item:start\");\n  const end = document.createComment(\"for:item:end\");\n  parent.insertBefore(start, reference);\n  parent.insertBefore(end, reference);\n  const loopScope = \{ ...scope, [");
    emit_string(item, out);
    append(out, "]: item };\n");
    var prop_arg = "undefined";
    if has_props {
        prop_arg = "props";
        const object = try component_props(source, component, child_id, plan, "loopScope");
        append(out, $"  const props = {object};\n");
    }
    var handler_arg = "undefined";
    if has_handlers {
        handler_arg = "handlers";
        const object = try component_handlers(source, component, child_id, plan, "loopScope");
        append(out, $"  const handlers = {object};\n");
    }
    var slot_arg = "undefined";
    if has_slots {
        slot_arg = "slots";
        const object = component_slots(source, component, "slotOwner");
        append(out, "  const slotOwner = { refresh: () => loopScope, update: () => instance.update() };\n");
        append(out, $"  const slots = {object};\n");
    }
    append(out, $"  const handle = {tag}.mountIntoBoundary(start, end, {prop_arg}, {handler_arg}, {slot_arg});\n  return \{ key: item?.id ?? item, start, end, handle \};\n\}\n\n");
    append(out, $"function updateForLoop_{start}(instance, scope, refs) \{\n  const iterable = ({iterable}) ?? [];\n  const previous = refs[{state}] ?? [];\n  const previousByKey = new Map(previous.map((record) => [record.key, record]));\n  const nextRecords = [];\n  for (const item of iterable) \{\n    const key = item?.id ?? item;\n    let record = previousByKey.get(key);\n    const loopScope = \{ ...scope, [");
    emit_string(item, out);
    append(out, "]: item };\n    if (record) {\n      previousByKey.delete(key);\n");
    if has_props {
        const object = try component_props(source, component, child_id, plan, "loopScope");
        append(out, $"      record.handle.setProps({object});\n");
    }
    if has_handlers {
        const object = try component_handlers(source, component, child_id, plan, "loopScope");
        append(out, $"      record.handle.setEventHandlers({object});\n");
    }
    if has_slots {
        const object = component_slots(source, component, "slotOwner");
        append(out, "      const slotOwner = { refresh: () => loopScope, update: () => instance.update() };\n");
        append(out, $"      record.handle.setSlots({object});\n");
    }
    if has_props or has_slots {
        append(out, "      record.handle.update();\n");
    }
    append(out, $"      moveBoundaryBefore(record.start, record.end, refs[{end}]);\n    \} else \{\n      record = createForComponentEntry_{start}(instance, scope, item, refs[{end}]);\n    \}\n    nextRecords.push(record);\n  \}\n  for (const record of previousByKey.values()) \{\n    if (record.handle && typeof record.handle.destroy === \"function\") \{\n      record.handle.destroy();\n    \}\n    replaceBetween(record.start, record.end, document.createDocumentFragment());\n    record.start.parentNode.removeChild(record.start);\n    record.end.parentNode.removeChild(record.end);\n  \}\n  refs[{state}] = nextRecords;\n\}\n\n");
    return;
}

fn validate_body(tree: &const RenderDocument, roots: &const List<usize>): void ! JavaScriptError {
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
            .component(value) => {}
            .for_loop(value) => {}
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
            .for_loop(value) => {
                try validate_body(tree, &value.body);
                const start = value.start_ref_id;
                const end = value.end_ref_id;
                const state = value.state_ref_id;
                const item = string.from(source[value.item_name.start..value.item_name.end]);
                const index = plan.find(id, EvaluatorSite.iterable, 0);
                if index is none {
                    throw JavaScriptError.evaluator_plan_mismatch;
                }
                const iterable = emit_call(&plan.records[index], "scope");
                if value.body.len() == 1 {
                    const child_id = value.body[0];
                    const child_payload = &tree.nodes[child_id].payload;
                    switch child_payload {
                        .component(component) => {
                            try emit_component_entry(source, &value, &component, child_id, plan, iterable, &out);
                            return string.from(out.view());
                        }
                        _ => {}
                    }
                }
                append(&out, $"function createForEntry_{start}(instance, scope, item, reference) \{\n  const parent = reference.parentNode;\n  const start = document.createComment(\"for:item:start\");\n  const end = document.createComment(\"for:item:end\");\n  parent.insertBefore(start, reference);\n  parent.insertBefore(end, reference);\n  const entryRefs = [];\n  let currentItem = item;\n  let loopScope = \{ ...scope, [");
                emit_string(item, &out);
                append(&out, "]: currentItem };\n  function update(nextScope, nextItem) {\n    if (arguments.length > 1) currentItem = nextItem;\n    const refs = entryRefs;\n    loopScope = { ...nextScope, [");
                emit_string(item, &out);
                append(&out, "]: currentItem };\n");
                try emit_fixed_updates(source, tree, &value.body, plan, &out, "loopScope", "entryRefs", "    ");
                append(&out, "  }\n  const fragment = document.createDocumentFragment();\n  fragment.__weiv_namespace = parent.localName === \"foreignObject\" ? undefined : parent.namespaceURI;\n");
                try emit_nodes_into(source, tree, &value.body, scope, plan, &out, "entryRefs", "fragment", "loopScope");
                append(&out, "  function destroy() {\n    const refs = entryRefs;\n");
                emit_destroy_nodes(tree, &value.body, &out, 2, "entryRefs");
                append(&out, "  }\n  replaceBetween(start, end, fragment);\n  update(scope, item);\n  return { key: item?.id ?? item, start, end, refs: entryRefs, update, destroy };\n}\n\n");
                append(&out, $"function updateForLoop_{start}(instance, scope, refs) \{\n  const iterable = ({iterable}) ?? [];\n  const previous = refs[{state}] ?? [];\n  const previousByKey = new Map(previous.map((record) => [record.key, record]));\n  const nextRecords = [];\n  for (const item of iterable) \{\n    const key = item?.id ?? item;\n    let record = previousByKey.get(key);\n    if (record) \{\n      previousByKey.delete(key);\n      record.update(scope, item);\n      moveBoundaryBefore(record.start, record.end, refs[{end}]);\n    \} else \{\n      record = createForEntry_{start}(instance, scope, item, refs[{end}]);\n    \}\n    nextRecords.push(record);\n  \}\n  for (const record of previousByKey.values()) \{\n    if (typeof record.destroy === \"function\") \{\n      record.destroy();\n    \}\n    replaceBetween(record.start, record.end, document.createDocumentFragment());\n    record.start.parentNode.removeChild(record.start);\n    record.end.parentNode.removeChild(record.end);\n  \}\n  refs[{state}] = nextRecords;\n\}\n\n");
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
            .for_loop(value) => {
                const start = value.start_ref_id;
                append(&out, $"function updateRegion_loop_{start}(instance, scope, refs) \{\n  updateForLoop_{start}(instance, scope, refs);\n\}\n");
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
            .for_loop(value) => {
                const state = value.state_ref_id;
                append(&out, $"  const __records_{state} = refs[{state}] ?? [];\n  for (const record of __records_{state}) \{\n    if (record.handle && typeof record.handle.destroy === \"function\") \{\n      record.handle.destroy();\n    \} else if (typeof record.destroy === \"function\") \{\n      record.destroy();\n    \}\n  \}\n");
            }
            _ => {}
        }
        id = id + 1;
    }
    return string.from(out.view());
}
