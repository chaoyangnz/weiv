// Operation: valid LIR tree -> independently owned browser tree; iterative logical-edge traversal.
import { LirDocument, LirAttribute, LirDirectiveEffect, LirElement, LirComponent, LirConditional, LirForLoop, LirSlotOutlet, LirSlotProvision } from .compiler.lower.lir;
import { RenderDocument, RenderNode, RenderPayload, RenderInterpolation, RenderElement, RenderConditional, RenderForLoop, RenderComponent, RenderSlotOutlet, RenderSlotProvision } from .compiler.backend.browser.render_tree.tree;

struct Visit {
    id: usize;
    finish: bool;
}
fn push_children(work: &List<Visit>, children: &const List<usize>): void {
    var i = children.len();
    while i > 0 {
        i = i - 1;
        work.push(Visit {
            id: children[i],
            finish: false
        });
    }
}
fn copy_ids(ids: &const List<usize>): List<usize> {
    var output = list<usize>();
    var i: usize = 0;
    while i < ids.len() {
        output.push(ids[i]);
        i = i + 1;
    }
    return output;
}
fn copy_attributes(attributes: &const List<LirAttribute>): List<LirAttribute> {
    var output = list<LirAttribute>();
    var i: usize = 0;
    while i < attributes.len() {
        const attribute = &attributes[i];
        output.push(LirAttribute {
            name: attribute.name,
            value: attribute.value
        });
        i = i + 1;
    }
    return output;
}
fn split_effects(effects: &const List<LirDirectiveEffect>, binds: bool): List<LirDirectiveEffect> {
    var output = list<LirDirectiveEffect>();
    var i: usize = 0;
    while i < effects.len() {
        const effect = &effects[i];
        switch effect {
            .bind(value) => {
                if binds {
                    output.push(.bind(value));
                }
            }
            .event(value) => {
                if not binds {
                    output.push(.event(value));
                }
            }
        }
        i = i + 1;
    }
    return output;
}

// Variant helpers make borrowed payload roots explicit before accessing owned fields.
fn push_element(work: &List<Visit>, value: &const LirElement): void {
    push_children(work, &value.children);
}
fn push_provision(work: &List<Visit>, value: &const LirSlotProvision): void {
    push_children(work, &value.children);
}
fn push_component(work: &List<Visit>, value: &const LirComponent): void {
    var p = value.slot_provisions.len();
    while p > 0 {
        p = p - 1;
        push_provision(work, &value.slot_provisions[p]);
    }
}
fn push_conditional(work: &List<Visit>, value: &const LirConditional): void {
    push_children(work, &value.alternate);
    push_children(work, &value.consequent);
}
fn push_loop(work: &List<Visit>, value: &const LirForLoop): void {
    push_children(work, &value.body);
}
fn push_outlet(work: &List<Visit>, value: &const LirSlotOutlet): void {
    push_children(work, &value.fallback_children);
}
fn make_element(value: &const LirElement, id: usize): RenderPayload {
    return .element(RenderElement {
        ref_id: id,
        tag_name: value.tag_name,
        attributes: copy_attributes(&value.attributes),
        bind_effects: split_effects(&value.effects, true),
        event_effects: split_effects(&value.effects, false),
        children: copy_ids(&value.children)
    });
}
fn make_conditional(value: &const LirConditional, id: usize): RenderPayload {
    return .conditional(RenderConditional {
        condition: value.condition,
        start_ref_id: id,
        end_ref_id: id + 1,
        state_ref_id: id + 2,
        consequent: copy_ids(&value.consequent),
        alternate: copy_ids(&value.alternate)
    });
}
fn make_loop(value: &const LirForLoop, id: usize): RenderPayload {
    return .for_loop(RenderForLoop {
        item_name: value.item_name,
        iterable_expr: value.iterable_expr,
        start_ref_id: id,
        end_ref_id: id + 1,
        state_ref_id: id + 2,
        body: copy_ids(&value.body)
    });
}
fn make_provision(value: &const LirSlotProvision): RenderSlotProvision {
    return {
        name: value.name,
        children: copy_ids(&value.children)
    };
}
fn make_component(value: &const LirComponent, id: usize): RenderPayload {
    var provisions = list<RenderSlotProvision>();
    var p: usize = 0;
    while p < value.slot_provisions.len() {
        provisions.push(make_provision(&value.slot_provisions[p]));
        p = p + 1;
    }
    return .component(RenderComponent {
        tag_name: value.tag_name,
        start_ref_id: id,
        end_ref_id: id + 1,
        handle_ref_id: id + 2,
        bind_effects: split_effects(&value.effects, true),
        event_effects: split_effects(&value.effects, false),
        slot_provisions: provisions
    });
}
fn make_outlet(value: &const LirSlotOutlet, id: usize): RenderPayload {
    return .slot_outlet(RenderSlotOutlet {
        name: value.name,
        start_ref_id: id,
        end_ref_id: id + 1,
        handle_ref_id: id + 2,
        fallback_children: copy_ids(&value.fallback_children)
    });
}

pub fn lower(document: &const LirDocument): RenderDocument {
    var bases = list<usize>();
    var i: usize = 0;
    while i < document.nodes.len() {
        bases.push(0);
        i = i + 1;
    }
    var work = list<Visit>();
    push_children(&work, &document.roots);
    var next: usize = 0;
    while work.len() > 0 {
        const visit = work.pop();
        const payload = &document.nodes[visit.id].payload;
        if visit.finish {
            bases[visit.id] = next;
            switch payload {
                .element(value) => {
                    next = next + 1;
                }
                .component(value) => {
                    next = next + 3;
                }
                _ => {
                    panic("Only elements and components allocate after their children");
                }
            }
        } else {
            switch payload {
                .text(value) => {}
                .interpolation(value) => {
                    bases[visit.id] = next;
                    next = next + 1;
                }
                .element(value) => {
                    work.push(Visit {
                        id: visit.id,
                        finish: true
                    });
                    push_element(&work, &value);
                }
                .component(value) => {
                    work.push(Visit {
                        id: visit.id,
                        finish: true
                    });
                    push_component(&work, &value);
                }
                .conditional(value) => {
                    bases[visit.id] = next;
                    next = next + 3;
                    push_conditional(&work, &value);
                }
                .for_loop(value) => {
                    bases[visit.id] = next;
                    next = next + 3;
                    push_loop(&work, &value);
                }
                .slot_outlet(value) => {
                    bases[visit.id] = next;
                    next = next + 3;
                    push_outlet(&work, &value);
                }
            }
        }
    }
    var output: RenderDocument = {
        nodes: list<RenderNode>(),
        roots: copy_ids(&document.roots),
        next_ref_id: next
    };
    i = 0;
    while i < document.nodes.len() {
        const source_payload = &document.nodes[i].payload;
        const id = bases[i];
        const payload: RenderPayload = switch source_payload {
            .text(value) => .text(value);
            .interpolation(value) => .interpolation(RenderInterpolation {
                ref_id: id,
                expression: value
            });
            .element(value) => make_element(&value, id);
            .conditional(value) => make_conditional(&value, id);
            .for_loop(value) => make_loop(&value, id);
            .component(value) => make_component(&value, id);
            .slot_outlet(value) => make_outlet(&value, id);
        };
        output.nodes.push(RenderNode {
            span: document.nodes[i].span,
            payload: payload
        });
        i = i + 1;
    }
    return output;
}
