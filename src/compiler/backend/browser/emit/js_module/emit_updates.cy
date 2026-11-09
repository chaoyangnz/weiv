// Operation: a non-structural render forest, evaluator plan and original graph -> updates.
import { RenderDocument, RenderElement } from .compiler.backend.browser.render_tree.tree;
import { RegionGraph, Region, RegionKind } from .compiler.backend.browser.region_graph;
import { EvaluatorPlan, EvaluatorSite } from .compiler.backend.browser.emit.evaluator_plan;
import { JavaScriptError } from .compiler.backend.browser.emit.javascript_errors;
import { append, emit_string } from .compiler.backend.browser.emit.js_module.write_javascript;
import { emit as emit_call } from .compiler.backend.browser.emit.js_module.emit_evaluator_call;
import { emit as emit_binding, suffix } from .compiler.backend.browser.emit.js_module.emit_binding_update;
import { region_update as emit_component_region } from .compiler.backend.browser.emit.js_module.emit_components;
import { updates as emit_slot_update } from .compiler.backend.browser.emit.js_module.emit_slot_outlets;
import .compiler.backend.browser.emit.js_module.module_fragments as fragments;
fn push_order(work: &List<usize>, children: &const List<usize>): void {
    var index = children.len();
    while index > 0 {
        index = index - 1;
        work.push(children[index]);
    }
}
fn render_order(tree: &const RenderDocument): List<usize> {
    var order = list<usize>();
    var work = list<usize>();
    push_order(&work, &tree.roots);
    while work.len() > 0 {
        const id = work.pop();
        order.push(id);
        const payload = &tree.nodes[id].payload;
        switch payload {
            .element(value) => {
                push_order(&work, &value.children);
            }
            .conditional(value) => {
                push_order(&work, &value.alternate);
                push_order(&work, &value.consequent);
            }
            .for_loop(value) => {
                push_order(&work, &value.body);
            }
            .slot_outlet(value) => {
                push_order(&work, &value.fallback_children);
            }
            .component(value) => {
                var index = value.slot_provisions.len();
                while index > 0 {
                    index = index - 1;
                    push_order(&work, &value.slot_provisions[index].children);
                }
            }
            _ => {}
        }
    }
    return order;
}
fn append_unrecorded_helpers(source: []const u8, tree: &const RenderDocument, plan: &const EvaluatorPlan, id: usize, functions: &List<u8>, nested_children: &List<usize>): void ! JavaScriptError {
    const payload = &tree.nodes[id].payload;
    switch payload {
        .slot_outlet(value) => {
            const selected: ?usize = id;
            append(functions, try emit_slot_update(source, tree, plan, selected));
        }
        .component(value) => {
            append(functions, try emit_component_region(source, tree, plan, id));
            nested_children.push(id);
        }
        _ => {}
    }
    return;
}
pub fn inside_structure(tree: &const RenderDocument, node_id: usize): bool {
    var n: usize = 0;
    while n < tree.nodes.len() {
        const payload = &tree.nodes[n].payload;
        switch payload {
            .conditional(value) => {
                var work = list<usize>();
                for child in value.consequent {
                    work.push(child);
                }
                for child in value.alternate {
                    work.push(child);
                }
                while work.len() > 0 {
                    const id = work.pop();
                    if id == node_id {
                        return true;
                    }
                    const descendant = &tree.nodes[id].payload;
                    switch descendant {
                        .element(element) => {
                            for child in element.children {
                                work.push(child);
                            }
                        }
                        _ => {}
                    }
                }
            }
            .for_loop(value) => {
                var work = list<usize>();
                for child in value.body {
                    work.push(child);
                }
                while work.len() > 0 {
                    const id = work.pop();
                    if id == node_id {
                        return true;
                    }
                    const descendant = &tree.nodes[id].payload;
                    switch descendant {
                        .element(element) => {
                            for child in element.children {
                                work.push(child);
                            }
                        }
                        _ => {}
                    }
                }
            }
            .slot_outlet(value) => {
                var work = list<usize>();
                for child in value.fallback_children {
                    work.push(child);
                }
                while work.len() > 0 {
                    const id = work.pop();
                    if id == node_id {
                        return true;
                    }
                    const descendant = &tree.nodes[id].payload;
                    switch descendant {
                        .element(element) => {
                            for child in element.children {
                                work.push(child);
                            }
                        }
                        _ => {}
                    }
                }
            }
            .component(value) => {
                var p: usize = 0;
                while p < value.slot_provisions.len() {
                    const provision = &value.slot_provisions[p];
                    var work = list<usize>();
                    var c: usize = 0;
                    while c < provision.children.len() {
                        work.push(provision.children[c]);
                        c = c + 1;
                    }
                    while work.len() > 0 {
                        const id = work.pop();
                        if id == node_id {
                            return true;
                        }
                        const descendant = &tree.nodes[id].payload;
                        switch descendant {
                            .element(element) => {
                                for child in element.children {
                                    work.push(child);
                                }
                            }
                            _ => {}
                        }
                    }
                    p = p + 1;
                }
            }
            _ => {}
        }
        n = n + 1;
    }
    return false;
}
fn static_value(source: []const u8, value: &const RenderElement, name: string): ?string {
    var i: usize = 0;
    while i < value.attributes.len() {
        const attribute = &value.attributes[i];
        if string.from(source[attribute.name.start..attribute.name.end]) == name {
            if attribute.value is span {
                return string.from(source[span.start..span.end]);
            }
            const present: ?string = "";
            return present;
        }
        i = i + 1;
    }
    return none;
}
fn invocation(kind: RegionKind, ref: usize, target: string): string {
    if kind == RegionKind.text {
        return $"updateRegion_text_{ref}(instance, scope, refs);\n";
    }
    const name = suffix(target);
    return $"updateRegion_attribute_{ref}_{name}(instance, scope, refs);\n";
}
fn guard(region: &const Region, out: &List<u8>): void {
    append(out, "  if (");
    var i: usize = 0;
    while i < region.dependency_names.len() {
        const dep = region.dependency_names[i];
        if i > 0 {
            append(out, " || ");
        }
        append(out, "dirtySet.has(");
        emit_string(dep, out);
        append(out, ")");
        if region.precise_import_name is name {
            if name == dep {
                append(out, " && !preciseBindingSet.has(");
                emit_string(dep, out);
                append(out, ")");
            }
        }
        i = i + 1;
    }
    if i > 0 {
        append(out, " || ");
    }
    const id = region.id;
    append(out, $"dirtyRegionSet.has({id})) \{\n    ");
}
fn append_owned_region(source: []const u8, tree: &const RenderDocument, plan: &const EvaluatorPlan, graph: &const RegionGraph, count: usize, functions: &List<u8>, calls: &List<u8>, dirty: &List<u8>): usize ! JavaScriptError {
    const region = &graph.regions[count];
    if region.id != count + 1 or region.node_id >= tree.nodes.len() {
        throw JavaScriptError.region_graph_mismatch;
    }
    const payload = &tree.nodes[region.node_id].payload;
    switch payload {
        .component(value) => {
            if region.kind != RegionKind.child or region.ref_id != value.handle_ref_id {
                throw JavaScriptError.region_graph_mismatch;
            }
            const ref = value.handle_ref_id;
            const statement = $"updateRegion_child_{ref}(instance, scope, refs);\n";
            append(calls, "  ");
            append(calls, statement);
            guard(region, dirty);
            append(dirty, statement);
            append(dirty, "  }\n");
            return count + 1;
        }
        .slot_outlet(value) => {
            if region.kind != RegionKind.slot or region.ref_id != value.handle_ref_id {
                throw JavaScriptError.region_graph_mismatch;
            }
            const ref = value.handle_ref_id;
            const statement = $"updateRegion_slot_{ref}(instance, scope, refs);\n";
            append(calls, "  ");
            append(calls, statement);
            guard(region, dirty);
            append(dirty, statement);
            append(dirty, "  }\n");
            return count + 1;
        }
        _ => {
            throw JavaScriptError.region_graph_mismatch;
        }
    }
}
pub fn emit(source: []const u8, tree: &const RenderDocument, plan: &const EvaluatorPlan, graph: &const RegionGraph): string ! JavaScriptError {
    var functions = list<u8>();
    var calls = list<u8>();
    var dirty = list<u8>();
    var count: usize = 0;
    const order = render_order(tree);
    var order_index: usize = 0;
    var last_node: ?usize = none;
    var nested_children = list<usize>();
    var i: usize = 0;
    // Plan records retain logical preorder even where arena allocation order differs.
    while i < plan.records.len() {
        const record = &plan.records[i];
        if last_node is previous {
            if previous != record.node_id {
                while order_index < order.len() and order[order_index] != record.node_id {
                    try append_unrecorded_helpers(source, tree, plan, order[order_index], &functions, &nested_children);
                    order_index = order_index + 1;
                }
                order_index = order_index + 1;
            }
        } else {
            while order_index < order.len() and order[order_index] != record.node_id {
                try append_unrecorded_helpers(source, tree, plan, order[order_index], &functions, &nested_children);
                order_index = order_index + 1;
            }
            order_index = order_index + 1;
        }
        last_node = record.node_id;
        const ordered_payload = &tree.nodes[record.node_id].payload;
        switch ordered_payload {
            .component(value) => {
                var found = false;
                for emitted in nested_children {
                    if emitted == record.node_id {
                        found = true;
                    }
                }
                if not found {
                    append(&functions, try emit_component_region(source, tree, plan, record.node_id));
                    nested_children.push(record.node_id);
                }
            }
            _ => {}
        }
        while count < graph.regions.len() and (graph.regions[count].kind == RegionKind.child or graph.regions[count].kind == RegionKind.slot) {
            count = try append_owned_region(source, tree, plan, graph, count, &functions, &calls, &dirty);
        }
        if inside_structure(tree, record.node_id) {
            const nested_payload = &tree.nodes[record.node_id].payload;
            switch nested_payload {
                .component(value) => {
                    var found = false;
                    for emitted in nested_children {
                        if emitted == record.node_id {
                            found = true;
                        }
                    }
                    if not found {
                        append(&functions, try emit_component_region(source, tree, plan, record.node_id));
                        nested_children.push(record.node_id);
                    }
                    i = i + 1;
                    continue;
                }
                _ => {}
            }
            if record.site == EvaluatorSite.interpolation {
                const payload = &tree.nodes[record.node_id].payload;
                switch payload {
                    .interpolation(value) => {
                        const ref = value.ref_id;
                        const call = emit_call(record, "scope");
                        append(&functions, $"function updateRegion_text_{ref}(instance, scope, refs) \{\n  const __next_text_{ref} = String(({call}) ?? \"\");\n  if (refs[{ref}].data !== __next_text_{ref}) \{\n    refs[{ref}].data = __next_text_{ref};\n  \}\n\}\n");
                    }
                    _ => {
                        throw JavaScriptError.evaluator_plan_mismatch;
                    }
                }
            } else if record.site == EvaluatorSite.binding {
                const payload = &tree.nodes[record.node_id].payload;
                switch payload {
                    .element(value) => {
                        if record.effect_index >= value.bind_effects.len() {
                            throw JavaScriptError.evaluator_plan_mismatch;
                        }
                        const effect = &value.bind_effects[record.effect_index];
                        switch effect {
                            .bind(binding) => {
                                const target = string.from(source[binding.name.start..binding.name.end]);
                                const ref = value.ref_id;
                                const name = suffix(target);
                                const call = emit_call(record, "scope");
                                append(&functions, $"function updateRegion_attribute_{ref}_{name}(instance, scope, refs) \{\n");
                                emit_binding(target, call, static_value(source, &value, target), ref, &functions);
                                append(&functions, "}\n");
                            }
                            _ => {
                                throw JavaScriptError.evaluator_plan_mismatch;
                            }
                        }
                    }
                    _ => {
                        throw JavaScriptError.evaluator_plan_mismatch;
                    }
                }
            }
            if record.site == EvaluatorSite.condition {
                const payload = &tree.nodes[record.node_id].payload;
                switch payload {
                    .conditional(value) => {
                        const ref = value.start_ref_id;
                        append(&functions, $"function updateRegion_conditional_{ref}(instance, scope, refs) \{\n  updateConditional_{ref}(instance, scope, refs);\n\}\n");
                    }
                    _ => {
                        throw JavaScriptError.evaluator_plan_mismatch;
                    }
                }
            }
            if record.site == EvaluatorSite.iterable {
                const payload = &tree.nodes[record.node_id].payload;
                switch payload {
                    .for_loop(value) => {
                        const ref = value.start_ref_id;
                        append(&functions, $"function updateRegion_loop_{ref}(instance, scope, refs) \{\n  updateForLoop_{ref}(instance, scope, refs);\n\}\n");
                    }
                    _ => {
                        throw JavaScriptError.evaluator_plan_mismatch;
                    }
                }
            }
            i = i + 1;
            continue;
        }
        const current_payload = &tree.nodes[record.node_id].payload;
        switch current_payload {
            .component(value) => {
                i = i + 1;
                continue;
            }
            .slot_outlet(value) => {
                i = i + 1;
                continue;
            }
            _ => {}
        }
        if record.site == EvaluatorSite.interpolation or record.site == EvaluatorSite.binding {
            const payload = &tree.nodes[record.node_id].payload;
            const call = emit_call(record, "scope");
            var ref: usize = 0;
            var kind = RegionKind.text;
            var target = "";
            switch payload {
                .interpolation(value) => {
                    if record.site != EvaluatorSite.interpolation {
                        throw JavaScriptError.evaluator_plan_mismatch;
                    }
                    ref = value.ref_id;
                    append(&functions, $"function updateRegion_text_{ref}(instance, scope, refs) \{\n");
                    append(&functions, $"  const __next_text_{ref} = String(({call}) ?? \"\");\n  if (refs[{ref}].data !== __next_text_{ref}) \{\n    refs[{ref}].data = __next_text_{ref};\n  \}\n\}\n");
                }
                .element(value) => {
                    if record.site != EvaluatorSite.binding or record.effect_index >= value.bind_effects.len() {
                        throw JavaScriptError.evaluator_plan_mismatch;
                    }
                    ref = value.ref_id;
                    kind = RegionKind.attribute;
                    const effect = &value.bind_effects[record.effect_index];
                    switch effect {
                        .bind(binding) => {
                            target = string.from(source[binding.name.start..binding.name.end]);
                        }
                        _ => {
                            throw JavaScriptError.evaluator_plan_mismatch;
                        }
                    }
                    const name = suffix(target);
                    append(&functions, $"function updateRegion_attribute_{ref}_{name}(instance, scope, refs) \{\n");
                    emit_binding(target, call, static_value(source, &value, target), ref, &functions);
                    append(&functions, "}\n");
                }
                _ => {
                    throw JavaScriptError.unsupported_template;
                }
            }
            if count >= graph.regions.len() {
                throw JavaScriptError.region_graph_mismatch;
            }
            const region = &graph.regions[count];
            if region.id != count + 1 or region.kind != kind or region.ref_id != ref or region.node_id != record.node_id {
                throw JavaScriptError.region_graph_mismatch;
            }
            if kind == RegionKind.attribute {
                if region.name is name {
                    if name != target {
                        throw JavaScriptError.region_graph_mismatch;
                    }
                } else {
                    throw JavaScriptError.region_graph_mismatch;
                }
            }
            const statement = invocation(kind, ref, target);
            append(&calls, "  ");
            append(&calls, statement);
            guard(region, &dirty);
            append(&dirty, statement);
            append(&dirty, "  }\n");
            count = count + 1;
        } else if record.site == EvaluatorSite.condition {
            const payload = &tree.nodes[record.node_id].payload;
            switch payload {
                .conditional(value) => {
                    if count >= graph.regions.len() {
                        throw JavaScriptError.region_graph_mismatch;
                    }
                    const region = &graph.regions[count];
                    if region.id != count + 1 or region.kind != RegionKind.conditional or region.ref_id != value.state_ref_id or region.node_id != record.node_id {
                        throw JavaScriptError.region_graph_mismatch;
                    }
                    const start = value.start_ref_id;
                    append(&functions, $"function updateRegion_conditional_{start}(instance, scope, refs) \{\n  updateConditional_{start}(instance, scope, refs);\n\}\n");
                    const statement = $"updateRegion_conditional_{start}(instance, scope, refs);\n";
                    append(&calls, "  ");
                    append(&calls, statement);
                    guard(region, &dirty);
                    append(&dirty, statement);
                    append(&dirty, "  }\n");
                    count = count + 1;
                }
                _ => {
                    throw JavaScriptError.evaluator_plan_mismatch;
                }
            }
        } else if record.site == EvaluatorSite.iterable {
            const payload = &tree.nodes[record.node_id].payload;
            switch payload {
                .for_loop(value) => {
                    if count >= graph.regions.len() {
                        throw JavaScriptError.region_graph_mismatch;
                    }
                    const region = &graph.regions[count];
                    if region.id != count + 1 or region.kind != RegionKind.loop or region.ref_id != value.state_ref_id or region.node_id != record.node_id {
                        throw JavaScriptError.region_graph_mismatch;
                    }
                    const start = value.start_ref_id;
                    append(&functions, $"function updateRegion_loop_{start}(instance, scope, refs) \{\n  updateForLoop_{start}(instance, scope, refs);\n\}\n");
                    const statement = $"updateRegion_loop_{start}(instance, scope, refs);\n";
                    append(&calls, "  ");
                    append(&calls, statement);
                    guard(region, &dirty);
                    append(&dirty, statement);
                    append(&dirty, "  }\n");
                    count = count + 1;
                }
                _ => {
                    throw JavaScriptError.evaluator_plan_mismatch;
                }
            }
        } else if record.site != EvaluatorSite.handler {
            throw JavaScriptError.unsupported_template;
        }
        i = i + 1;
    }
    while order_index < order.len() {
        try append_unrecorded_helpers(source, tree, plan, order[order_index], &functions, &nested_children);
        order_index = order_index + 1;
    }
    while count < graph.regions.len() and (graph.regions[count].kind == RegionKind.child or graph.regions[count].kind == RegionKind.slot) {
        count = try append_owned_region(source, tree, plan, graph, count, &functions, &calls, &dirty);
    }
    if count != graph.regions.len() {
        throw JavaScriptError.region_graph_mismatch;
    }
    append(&functions, "\n");
    append(&functions, fragments.update_header());
    append(&functions, string.from(calls.view()));
    append(&functions, fragments.update_footer());
    append(&functions, "\n");
    append(&functions, fragments.dirty_header());
    append(&functions, string.from(dirty.view()));
    append(&functions, fragments.dirty_footer());
    return string.from(functions.view());
}
