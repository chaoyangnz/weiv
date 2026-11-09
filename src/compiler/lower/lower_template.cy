// Operation: paired template models + bound expression facts -> owned target-neutral LIR.
import { Span } from .compiler.source;
import { TemplateDocument, TemplateElement, TemplateSlotOutlet } from .compiler.parser.template.ast;
import { NormalizedDocument, NormalizedElement } from .compiler.parser.template.normalized;
import { TemplateBindings } from .compiler.sema.template_bindings;
import .compiler.parser.template.scan;
import { LirDocument, LirNode, LirPayload, LirAttribute, LirDirectiveEffect, LirEffectTarget, LirElement, LirComponent, LirSlotProvision, LirConditional, LirForLoop, LirSlotOutlet, LirExpressionFacts, LirExpressionReference } from .compiler.lower.lir;

pub enum LowerError {
    invalid_slot_placement;
    invalid_slot_template_placement;
}
struct ParentFrame {
    end: usize;
    component: bool;
}

fn element_of(raw: &const TemplateDocument, id: usize): TemplateElement {
    return switch raw.nodes[id].payload {
        .element(value) => value;
        _ => {
            panic("Normalized element requires its raw element");
        }
    };
}
fn is_component(source: []const u8, tag: Span): bool {
    return tag.end > tag.start and source[tag.start] >= 65 and source[tag.start] <= 90;
}
fn slot_name(raw: &const TemplateDocument, normalized: &const NormalizedDocument, element: NormalizedElement): ?Span {
    var i = element.directives_start;
    while i < element.directives_start + element.directives_count {
        const directive = &raw.directives[normalized.directive_ids[i]];
        switch directive.payload {
            .slot_assign(name) => {
                return name;
            }
            _ => {}
        }
        i = i + 1;
    }
    return none;
}
fn mapped(ids: &const List<?usize>, id: usize): usize {
    if ids[id] is result {
        return result;
    }
    panic("Only projected template groups may be omitted from LIR");
}
fn children(normalized: &const NormalizedDocument, ids: &const List<?usize>, start: usize, end: usize): List<usize> {
    var result = list<usize>();
    var child = start;
    while child < end {
        result.push(mapped(ids, child));
        child = normalized.nodes[child].subtree_end;
    }
    return result;
}
fn effects(raw: &const TemplateDocument, normalized: &const NormalizedDocument, element: NormalizedElement): List<LirDirectiveEffect> {
    var result = list<LirDirectiveEffect>();
    var i = element.directives_start;
    while i < element.directives_start + element.directives_count {
        const directive = &raw.directives[normalized.directive_ids[i]];
        switch directive.payload {
            .event(value) => {
                result.push(.event(LirEffectTarget {
                    name: value.name,
                    expression: value.expression
                }));
            }
            .bind(value) => {
                result.push(.bind(LirEffectTarget {
                    name: value.name,
                    expression: value.expression
                }));
            }
            .slot_assign(value) => {}
            _ => {
                panic("Normalized elements cannot retain structural directives");
            }
        }
        i = i + 1;
    }
    return result;
}
fn attributes(raw: &const TemplateDocument, element: TemplateElement): List<LirAttribute> {
    var result = list<LirAttribute>();
    var i = element.attributes_start;
    while i < element.attributes_start + element.attributes_count {
        const attribute = &raw.attributes[i];
        result.push(LirAttribute {
            name: attribute.name,
            value: attribute.value
        });
        i = i + 1;
    }
    return result;
}
fn same_name(source: []const u8, a: ?Span, b: ?Span): bool {
    if a is left {
        if b is right {
            return scan.equal_spans(source, left, right);
        }
        return false;
    }
    if b is none {
        return true;
    }
    return false;
}
fn provisions(source: []const u8, raw: &const TemplateDocument, normalized: &const NormalizedDocument, ids: &const List<?usize>, start: usize, end: usize): List<LirSlotProvision> {
    var result = list<LirSlotProvision>();
    var child = start;
    while child < end {
        var name: ?Span = none;
        var group = false;
        switch normalized.nodes[child].payload {
            .element(element) => {
                const original = element_of(raw, element.raw_node);
                name = slot_name(raw, normalized, element);
                group = scan.equals(source, original.tag_name, "template");
            }
            _ => {}
        }
        var found: ?usize = none;
        var i: usize = 0;
        while i < result.len() {
            const existing = &result[i];
            if same_name(source, existing.name, name) {
                found = i;
            }
            i = i + 1;
        }
        var target: usize = 0;
        if found is index {
            target = index;
        } else {
            target = result.len();
            result.push(LirSlotProvision {
                name: name,
                children: list<usize>()
            });
        }
        const provision = result.get_mut(target);
        if group {
            var inner = child + 1;
            while inner < normalized.nodes[child].subtree_end {
                provision.children.push(mapped(ids, inner));
                inner = normalized.nodes[inner].subtree_end;
            }
        } else {
            provision.children.push(mapped(ids, child));
        }
        child = normalized.nodes[child].subtree_end;
    }
    return result;
}

pub fn lower(source: []const u8, raw: &const TemplateDocument, normalized: &const NormalizedDocument, bindings: &const TemplateBindings): LirDocument ! LowerError {
    var output: LirDocument = {
        nodes: list<LirNode>(),
        roots: list<usize>(),
        expressions: list<LirExpressionFacts>()
    };
    var e: usize = 0;
    while e < bindings.expressions.len() {
        const expression = &bindings.expressions[e];
        var references = list<LirExpressionReference>();
        var r: usize = 0;
        while r < expression.references.len() {
            const reference = &expression.references[r];
            references.push(LirExpressionReference {
                name: reference.name,
                call: reference.call
            });
            r = r + 1;
        }
        output.expressions.push(LirExpressionFacts {
            source: expression.source,
            references: references
        });
        e = e + 1;
    }
    var ids = list<?usize>();
    var parents = list<ParentFrame>();
    var i: usize = 0;
    while i < normalized.nodes.len() {
        while parents.len() > 0 and parents[parents.len() - 1].end <= i {
            const _ = parents.pop();
        }
        const node = normalized.nodes[i];
        var omitted = false;
        var component = false;
        switch node.payload {
            .element(element) => {
                const original = element_of(raw, element.raw_node);
                const named = slot_name(raw, normalized, element);
                const projected = parents.len() > 0 and parents[parents.len() - 1].component;
                if scan.equals(source, original.tag_name, "template") {
                    if not projected {
                        throw LowerError.invalid_slot_template_placement;
                    }
                    if named is none {
                        throw LowerError.invalid_slot_template_placement;
                    }
                    omitted = true;
                } else {
                    if named is name {
                        if not projected {
                            throw LowerError.invalid_slot_placement;
                        }
                    }
                    component = is_component(source, original.tag_name);
                }
            }
            _ => {}
        }
        if omitted {
            ids.push(none);
        } else {
            const id: ?usize = output.nodes.len();
            ids.push(id);
            output.nodes.push(LirNode {
                span: node.span,
                payload: .text(Span {
                    start: 0,
                    end: 0
                })
            });
        }
        parents.push(ParentFrame {
            end: node.subtree_end,
            component: component
        });
        i = i + 1;
    }
    output.roots = children(normalized, &ids, 0, normalized.nodes.len());
    i = 0;
    while i < normalized.nodes.len() {
        if ids[i] is id {
            const node = normalized.nodes[i];
            const payload: LirPayload = switch node.payload {
                .text(span) => .text(span);
                .interpolation(span) => .interpolation(span);
                .conditional(branch) => .conditional(LirConditional {
                    condition: branch.condition,
                    consequent: children(normalized, &ids, i + 1, branch.alternate_start),
                    alternate: children(normalized, &ids, branch.alternate_start, node.subtree_end)
                });
                .for_loop(loop) => .for_loop(LirForLoop {
                    item_name: loop.item_name,
                    iterable_expr: loop.iterable_expr,
                    body: children(normalized, &ids, i + 1, node.subtree_end)
                });
                .slot_outlet(raw_id) => {
                    const outlet: TemplateSlotOutlet = switch raw.nodes[raw_id].payload {
                        .slot_outlet(value) => value;
                        _ => {
                            panic("Expected raw slot outlet");
                        }
                    };
                    yield .slot_outlet(LirSlotOutlet {
                        name: outlet.name,
                        fallback_children: children(normalized, &ids, i + 1, node.subtree_end)
                    });
                }
                .element(element) => {
                    const original = element_of(raw, element.raw_node);
                    if is_component(source, original.tag_name) {
                        yield .component(LirComponent {
                            tag_name: original.tag_name,
                            effects: effects(raw, normalized, element),
                            slot_provisions: provisions(source, raw, normalized, &ids, i + 1, node.subtree_end)
                        });
                    }
                    yield .element(LirElement {
                        tag_name: original.tag_name,
                        attributes: attributes(raw, original),
                        effects: effects(raw, normalized, element),
                        children: children(normalized, &ids, i + 1, node.subtree_end)
                    });
                }
            };
            const target = output.nodes.get_mut(id);
            target.payload = payload;
        }
        i = i + 1;
    }
    return output;
}
