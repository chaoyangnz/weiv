// Coordinator operation: fixed-topology template and selected state -> ES module.
import { BrowserComponent } from .compiler.backend.browser.component;
import { ImportOverride, JavaScriptModule } from .compiler.backend.browser.emit.javascript_module;
import { JavaScriptError } from .compiler.backend.browser.emit.javascript_errors;
import { compute } from .compiler.backend.browser.compute_scope_id;
import { emit as emit_css } from .compiler.backend.browser.emit.emit_scoped_css;
import { append, emit_string } from .compiler.backend.browser.emit.js_module.write_javascript;
import { emit as emit_imports } from .compiler.backend.browser.emit.js_module.emit_module_imports;
import { emit as emit_setup } from .compiler.backend.browser.emit.js_module.emit_setup;
import { validate, emit as emit_dom } from .compiler.backend.browser.emit.js_module.emit_dom;
import { emit as emit_metadata } from .compiler.backend.browser.emit.js_module.emit_tracked_metadata;
import .compiler.backend.browser.emit.js_module.module_fragments as fragments;
import { build, EvaluatorError } from .compiler.backend.browser.emit.build_evaluator_plan;
import { emit as emit_updates } from .compiler.backend.browser.emit.js_module.emit_updates;
import { emit as emit_conditionals } from .compiler.backend.browser.emit.js_module.emit_conditionals;
import { emit as emit_loops } from .compiler.backend.browser.emit.js_module.emit_loops;
import { emit as emit_slot_outlets } from .compiler.backend.browser.emit.js_module.emit_slot_outlets;
import { emit as emit_projected_slots } from .compiler.backend.browser.emit.js_module.emit_projected_slots;
import { CellSelection, empty } from .compiler.backend.browser.emit.cell_selection;
import { select_into } from .compiler.backend.browser.emit.select_local_state;
import { emit as emit_destroy_nodes } from .compiler.backend.browser.emit.js_module.emit_destroy_nodes;
import { RenderDocument } from .compiler.backend.browser.render_tree.tree;
import { EvaluatorPlan } from .compiler.backend.browser.emit.evaluator_plan;

struct StructuralVisit {
    id: usize;
    finish: bool;
}
fn push_structural_children(work: &List<StructuralVisit>, children: &const List<usize>): void {
    var index = children.len();
    while index > 0 {
        index = index - 1;
        work.push(StructuralVisit {
            id: children[index],
            finish: false
        });
    }
}
fn emit_structural_helpers(source: []const u8, tree: &const RenderDocument, scope: string, plan: &const EvaluatorPlan, out: &List<u8>): void ! JavaScriptError {
    var work = list<StructuralVisit>();
    push_structural_children(&work, &tree.roots);
    while work.len() > 0 {
        const visit = work.pop();
        const payload = &tree.nodes[visit.id].payload;
        switch payload {
            .element(value) => {
                push_structural_children(&work, &value.children);
            }
            .conditional(value) => {
                append(out, try emit_conditionals(source, tree, scope, plan, visit.id));
                push_structural_children(&work, &value.alternate);
                push_structural_children(&work, &value.consequent);
            }
            .for_loop(value) => {
                append(out, try emit_loops(source, tree, scope, plan, visit.id));
                push_structural_children(&work, &value.body);
            }
            .slot_outlet(value) => {
                append(out, try emit_slot_outlets(source, tree, scope, plan, visit.id));
                push_structural_children(&work, &value.fallback_children);
            }
            .component(value) => {
                if visit.finish {
                    append(out, try emit_projected_slots(source, tree, scope, plan, visit.id));
                } else {
                    work.push(StructuralVisit {
                        id: visit.id,
                        finish: true
                    });
                    var index = value.slot_provisions.len();
                    while index > 0 {
                        index = index - 1;
                        push_structural_children(&work, &value.slot_provisions[index].children);
                    }
                }
            }
            _ => {}
        }
    }
    return;
}

pub fn emit(component: &const BrowserComponent, overrides: &const List<ImportOverride>): JavaScriptModule ! JavaScriptError {
    const selection = empty();
    return try emit_with_selection(component, overrides, &selection);
}

pub fn emit_with_local_state(component: &const BrowserComponent, overrides: &const List<ImportOverride>): JavaScriptModule ! JavaScriptError {
    var selection = empty();
    select_into(component, &selection);
    return try emit_with_selection(component, overrides, &selection);
}

pub fn emit_with_selection(component: &const BrowserComponent, overrides: &const List<ImportOverride>, selection: &const CellSelection): JavaScriptModule ! JavaScriptError {
    try validate(&component.render_tree);
    const scope = compute(component.unit.source_path);
    const css = emit_css(&component.unit) catch (code) {
        throw JavaScriptError.unterminated_rule;
    };
    const bytes = component.unit.source.bytes();
    const template_span = component.unit.sfc_document.template.content_span;
    const template = bytes[template_span.start..template_span.end];
    const plan = build(template, &component.render_tree, &component.unit.script.facts) catch (code) {
        if code == EvaluatorError.unsupported_render_expression {
            throw JavaScriptError.unsupported_render_expression;
        }
        if code == EvaluatorError.unsupported_handler_expression {
            throw JavaScriptError.unsupported_handler_expression;
        }
        if code == EvaluatorError.reserved_identifier {
            throw JavaScriptError.reserved_evaluator_identifier;
        }
        throw JavaScriptError.backend_failure;
    };
    const setup = try emit_setup(&component.unit, plan.code, selection);
    const imports = emit_imports(&component.unit.script.facts, overrides);
    const create = try emit_dom(template, &component.render_tree, scope, &plan);
    var out = list<u8>();
    append(&out, "import { isObservable as __weiv_isObservable, createCell as __weiv_createCell, createCellScope as __weiv_createCellScope, unbindCellValue as __weiv_unbindCellValue, normalizeCellValue as __weiv_normalizeCellValue, cellAssignmentTarget as __weiv_cellAssignmentTarget, bindingObject as __weiv_bindingObject, bindingIterator as __weiv_bindingIterator, initializeClassName as __weiv_initializeClassName } from \"weiv:cells\";\n");
    var publisher_index: usize = 0;
    var subscription_index: usize = 0;
    while subscription_index < selection.managed_subscriptions.len() {
        const subscription = &selection.managed_subscriptions[subscription_index];
        append(&out, $"import \{ moduleState as __weiv_publisher_{publisher_index} \} from ");
        emit_string(subscription.specifier, &out);
        append(&out, ";\n");
        publisher_index = publisher_index + 1;
        subscription_index = subscription_index + 1;
    }
    append(&out, imports);
    append(&out, fragments.prelude());
    try emit_structural_helpers(template, &component.render_tree, scope, &plan, &out);
    append(&out, setup);
    append(&out, "\n");
    append(&out, $"export const scopeId = \"{scope}\";\nexport const css = ");
    emit_string(css, &out);
    append(&out, ";\n\n");
    append(&out, emit_metadata(&component.region_graph));
    append(&out, "\n");
    append(&out, create);
    append(&out, "\n");
    append(&out, try emit_updates(template, &component.render_tree, &plan, &component.region_graph));
    append(&out, "\n");
    append(&out, fragments.destroy_header());
    emit_destroy_nodes(&component.render_tree, &component.render_tree.roots, &out, 1, "refs");
    append(&out, fragments.destroy_footer());
    append(&out, fragments.mount_exports());
    return {
        code: string.from(out.view()),
        scope_id: scope,
        css: css
    };
}
