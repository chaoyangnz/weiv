// Operation: template bytes -> raw template AST and source ranges.
import { Span } from .compiler.source;
import { TemplateAttribute, TemplateDocument, TemplateElement, TemplateNode, TemplateSlotOutlet, TemplateDirective } from .compiler.parser.template.ast;
import .compiler.parser.template.scan;

import { TemplateParseError } from .compiler.parser.template.errors;
import { split as split_directives } from .compiler.parser.template.split_directives;

fn attributes(source: []const u8, bounds: Span, output: &List<TemplateAttribute>): void ! TemplateParseError {
    var i = bounds.start;
    while i < bounds.end {
        const name_start = i;
        while i < bounds.end and not scan.whitespace(source[i]) and source[i] != 61 {
            i = i + 1;
        }
        const name: Span = {
            start: name_start,
            end: i
        };
        while i < bounds.end and scan.whitespace(source[i]) {
            i = i + 1;
        }
        var value: ?Span = none;
        if i < bounds.end and source[i] == 61 {
            i = i + 1;
            while i < bounds.end and scan.whitespace(source[i]) {
                i = i + 1;
            }
            if i < bounds.end and source[i] == 34 {
                i = i + 1;
                const start = i;
                while i < bounds.end and source[i] != 34 {
                    i = i + 1;
                }
                if i >= bounds.end {
                    throw TemplateParseError.unterminated_tag;
                }
                value = Span {
                    start: start,
                    end: i
                };
                i = i + 1;
            } else {
                const start = i;
                while i < bounds.end and not scan.whitespace(source[i]) {
                    i = i + 1;
                }
                value = Span {
                    start: start,
                    end: i
                };
            }
        }
        output.push(TemplateAttribute {
            name: name,
            value: value,
            span: {
                start: name_start,
                end: i
            }
        });
        while i < bounds.end and scan.whitespace(source[i]) {
            i = i + 1;
        }
    }
    return;
}

fn close_element(source: []const u8, start: usize, document: &TemplateDocument, stack: &List<usize>): usize ! TemplateParseError {
    if stack.len() == 0 {
        throw TemplateParseError.unexpected_close_tag;
    }
    const id = stack.pop();
    var node = document.nodes[id];
    const element: TemplateElement = switch node.payload {
        .element(value) => value;
        _ => {
            panic("Open element stack must reference an element");
        }
    };
    const name_end = start + 2 + element.tag_name.end - element.tag_name.start;
    if name_end >= source.len() {
        throw TemplateParseError.mismatched_close_tag;
    }
    if not scan.equal_spans(source, {
        start: start + 2,
        end: name_end
    }, element.tag_name) {
        throw TemplateParseError.mismatched_close_tag;
    }
    if source[name_end] != 62 and not scan.whitespace(source[name_end]) {
        throw TemplateParseError.mismatched_close_tag;
    }
    var gt = name_end;
    while gt < source.len() and source[gt] != 62 {
        gt = gt + 1;
    }
    if gt == source.len() {
        throw TemplateParseError.unterminated_tag;
    }
    node.span.end = gt + 1;
    node.subtree_end = document.nodes.len();
    document.nodes[id] = node;
    try finish_slot(source, document, id);
    return gt + 1;
}

pub fn parse(source: []const u8): TemplateDocument ! TemplateParseError {
    var document: TemplateDocument = {
        nodes: list<TemplateNode>(),
        attributes: list<TemplateAttribute>(),
        directives: list<TemplateDirective>()
    };
    var stack = list<usize>();
    var i: usize = 0;
    while i < source.len() {
        if scan.starts_with(source, i, "{{") {
            const close = scan.find(source, {
                start: i + 2,
                end: source.len()
            }, "}}");
            if close is none {
                throw TemplateParseError.unterminated_interpolation;
            }
            document.nodes.push(TemplateNode {
                span: {
                    start: i,
                    end: close + 2
                },
                payload: .interpolation(scan.trim(source, i + 2, close)),
                subtree_end: document.nodes.len() + 1
            });
            i = close + 2;
        } else if source[i] == 60 {
            if scan.starts_with(source, i, "</") {
                i = try close_element(source, i, &document, &stack);
            } else {
                const start = i;
                const gt = scan.open_tag_end(source, start);
                if gt is none {
                    throw TemplateParseError.unterminated_tag;
                }
                const explicit_self_closing = gt > start and source[gt - 1] == 47;
                var inner_end = gt;
                if explicit_self_closing {
                    inner_end = gt - 1;
                }
                const inner = scan.trim(source, start + 1, inner_end);
                var name_end = inner.start;
                while name_end < inner.end and not scan.whitespace(source[name_end]) {
                    name_end = name_end + 1;
                }
                if name_end == inner.start {
                    throw TemplateParseError.unterminated_tag;
                }
                const name: Span = {
                    start: inner.start,
                    end: name_end
                };
                const first_attribute = document.attributes.len();
                const first_directive = document.directives.len();
                var raw = list<TemplateAttribute>();
                try attributes(source, scan.trim(source, name_end, inner.end), &raw);
                try split_directives(source, raw.view(), &document);
                const id = document.nodes.len();
                document.nodes.push(TemplateNode {
                    span: {
                        start: start,
                        end: gt + 1
                    },
                    payload: .element(TemplateElement {
                        tag_name: name,
                        attributes_start: first_attribute,
                        attributes_count: document.attributes.len() - first_attribute,
                        directives_start: first_directive,
                        directives_count: document.directives.len() - first_directive
                    }),
                    subtree_end: id + 1
                });
                if not explicit_self_closing and not scan.void_tag(source, name) {
                    stack.push(id);
                } else {
                    try finish_slot(source, &document, id);
                }
                i = gt + 1;
            }
        } else {
            const start = i;
            while i < source.len() and source[i] != 60 and not scan.starts_with(source, i, "{{") {
                i = i + 1;
            }
            const meaningful = scan.trim(source, start, i);
            if meaningful.start != meaningful.end {
                document.nodes.push(TemplateNode {
                    span: {
                        start: start,
                        end: i
                    },
                    payload: .text(Span {
                        start: start,
                        end: i
                    }),
                    subtree_end: document.nodes.len() + 1
                });
            }
        }
    }
    if stack.len() != 0 {
        throw TemplateParseError.mismatched_close_tag;
    }
    return document;
}

fn finish_slot(source: []const u8, document: &TemplateDocument, id: usize): void ! TemplateParseError {
    var node = document.nodes[id];
    const element: TemplateElement = switch node.payload {
        .element(value) => value;
        _ => {
            panic("Only elements can become slot outlets");
        }
    };
    if not scan.equals(source, element.tag_name, "slot") {
        return;
    }
    if element.directives_count != 0 {
        throw TemplateParseError.invalid_slot_outlet;
    }
    var name: ?Span = none;
    var i = element.attributes_start;
    const end = i + element.attributes_count;
    while i < end {
        const attribute = document.attributes[i];
        if not scan.equals(source, attribute.name, "name") {
            throw TemplateParseError.invalid_slot_outlet;
        }
        if name is previous {
            throw TemplateParseError.invalid_slot_outlet;
        }
        if attribute.value is value {
            name = value;
        } else {
            throw TemplateParseError.invalid_slot_outlet;
        }
        i = i + 1;
    }
    node.payload = .slot_outlet(TemplateSlotOutlet {
        name: name,
        attributes_start: element.attributes_start,
        attributes_count: element.attributes_count
    });
    document.nodes[id] = node;
    return;
}
