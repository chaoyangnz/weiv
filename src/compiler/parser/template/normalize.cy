// Operation: immutable raw template AST -> normalized nodes and kept directive IDs.
import { Span } from .compiler.source;
import { TemplateDocument, TemplateElement, TemplateFor, TemplateDirectivePayload } from .compiler.parser.template.ast;
import { NormalizedDocument, NormalizedNode, NormalizedElement, NormalizedConditional, NormalizedLoop } from .compiler.parser.template.normalized;

pub enum NormalizeError {
    unexpected_else;
}

struct RawSequence {
    next: usize;
    end: usize;
}

union NormalizeTask {
    sequence: RawSequence;
    plain: usize;
    alternate: usize;
    finish: usize;
}

fn first_if(raw: &const TemplateDocument, element: TemplateElement): ?Span {
    var i = element.directives_start;
    while i < element.directives_start + element.directives_count {
        switch raw.directives[i].payload {
            .if_expr(value) => {
                return value;
            }
            _ => {}
        }
        i = i + 1;
    }
    return none;
}

fn first_for(raw: &const TemplateDocument, element: TemplateElement): ?TemplateFor {
    var i = element.directives_start;
    while i < element.directives_start + element.directives_count {
        switch raw.directives[i].payload {
            .for_expr(value) => {
                return value;
            }
            _ => {}
        }
        i = i + 1;
    }
    return none;
}

fn has_else(raw: &const TemplateDocument, element: TemplateElement): bool {
    var i = element.directives_start;
    while i < element.directives_start + element.directives_count {
        switch raw.directives[i].payload {
            .else_branch => {
                return true;
            }
            _ => {}
        }
        i = i + 1;
    }
    return false;
}

fn structural(payload: TemplateDirectivePayload): bool {
    return switch payload {
        .if_expr(value) => true;
        .else_branch => true;
        .for_expr(value) => true;
        .event(value) => false;
        .bind(value) => false;
        .slot_assign(value) => false;
    };
}

fn plain(raw: &const TemplateDocument, output: &NormalizedDocument, tasks: &List<NormalizeTask>, raw_id: usize): void {
    const node = raw.nodes[raw_id];
    const id = output.nodes.len();
    switch node.payload {
        .element(element) => {
            const first = output.directive_ids.len();
            var i = element.directives_start;
            while i < element.directives_start + element.directives_count {
                if not structural(raw.directives[i].payload) {
                    output.directive_ids.push(i);
                }
                i = i + 1;
            }
            output.nodes.push(NormalizedNode {
                span: node.span,
                payload: .element(NormalizedElement {
                    raw_node: raw_id,
                    directives_start: first,
                    directives_count: output.directive_ids.len() - first
                }),
                subtree_end: id + 1
            });
            tasks.push(.finish(id));
            tasks.push(.sequence(RawSequence {
                next: raw_id + 1,
                end: node.subtree_end
            }));
        }
        .slot_outlet(outlet) => {
            output.nodes.push(NormalizedNode {
                span: node.span,
                payload: .slot_outlet(raw_id),
                subtree_end: id + 1
            });
            tasks.push(.finish(id));
            tasks.push(.sequence(RawSequence {
                next: raw_id + 1,
                end: node.subtree_end
            }));
        }
        .text(text) => {
            output.nodes.push(NormalizedNode {
                span: node.span,
                payload: .text(text),
                subtree_end: id + 1
            });
        }
        .interpolation(expression) => {
            output.nodes.push(NormalizedNode {
                span: node.span,
                payload: .interpolation(expression),
                subtree_end: id + 1
            });
        }
    }
}

fn sequence(raw: &const TemplateDocument, output: &NormalizedDocument, tasks: &List<NormalizeTask>, input: RawSequence): void ! NormalizeError {
    if input.next >= input.end {
        return;
    }
    const raw_id = input.next;
    const node = raw.nodes[raw_id];
    switch node.payload {
        .element(element) => {
            const condition = first_if(raw, element);
            const loop = first_for(raw, element);
            if condition is expression {
                var next = node.subtree_end;
                var alternate: ?usize = none;
                if next < input.end {
                    switch raw.nodes[next].payload {
                        .element(sibling) => {
                            if has_else(raw, sibling) {
                                alternate = next;
                                next = raw.nodes[next].subtree_end;
                            }
                        }
                        _ => {}
                    }
                }
                const id = output.nodes.len();
                output.nodes.push(NormalizedNode {
                    span: node.span,
                    payload: .conditional(NormalizedConditional {
                        condition: expression,
                        alternate_start: id + 1
                    }),
                    subtree_end: id + 1
                });
                tasks.push(.sequence(RawSequence {
                    next: next,
                    end: input.end
                }));
                tasks.push(.finish(id));
                if alternate is branch {
                    tasks.push(.plain(branch));
                }
                tasks.push(.alternate(id));
                tasks.push(.plain(raw_id));
            } else if loop is value {
                const id = output.nodes.len();
                output.nodes.push(NormalizedNode {
                    span: node.span,
                    payload: .for_loop(NormalizedLoop {
                        item_name: value.item_name,
                        iterable_expr: value.iterable_expr
                    }),
                    subtree_end: id + 1
                });
                tasks.push(.sequence(RawSequence {
                    next: node.subtree_end,
                    end: input.end
                }));
                tasks.push(.finish(id));
                tasks.push(.plain(raw_id));
            } else if has_else(raw, element) {
                throw NormalizeError.unexpected_else;
            } else {
                tasks.push(.sequence(RawSequence {
                    next: node.subtree_end,
                    end: input.end
                }));
                tasks.push(.plain(raw_id));
            }
        }
        _ => {
            tasks.push(.sequence(RawSequence {
                next: node.subtree_end,
                end: input.end
            }));
            tasks.push(.plain(raw_id));
        }
    }
    return;
}

pub fn normalize(raw: &const TemplateDocument): NormalizedDocument ! NormalizeError {
    var output: NormalizedDocument = {
        nodes: list<NormalizedNode>(),
        directive_ids: list<usize>()
    };
    var tasks = list<NormalizeTask>();
    tasks.push(.sequence(RawSequence {
        next: 0,
        end: raw.nodes.len()
    }));
    while tasks.len() != 0 {
        const task = tasks.pop();
        switch task {
            .sequence(input) => {
                try sequence(raw, &output, &tasks, input);
            }
            .plain(id) => {
                plain(raw, &output, &tasks, id);
            }
            .finish(id) => {
                var node = output.nodes[id];
                node.subtree_end = output.nodes.len();
                output.nodes[id] = node;
            }
            .alternate(id) => {
                var node = output.nodes[id];
                var conditional: NormalizedConditional = switch node.payload {
                    .conditional(value) => value;
                    _ => {
                        panic("Alternate marker requires a conditional");
                    }
                };
                conditional.alternate_start = output.nodes.len();
                node.payload = .conditional(conditional);
                output.nodes[id] = node;
            }
        }
    }
    return output;
}
