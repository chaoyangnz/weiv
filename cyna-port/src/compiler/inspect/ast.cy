// Operation: parsed SFC and raw template AST -> reference text inspection.
import { SfcDocument } from .compiler.parser.sfc.ast;
import { TemplateDocument, TemplateDirective } from .compiler.parser.template.ast;
import { Span } from .compiler.source;
import { append } from .compiler.backend.browser.emit.js_module.write_javascript;

fn text(source: []const u8, span: Span): string {
    return string.from(source[span.start..span.end]);
}

fn indent(out: &List<u8>, depth: usize): void {
    var i: usize = 0;
    while i < depth {
        append(out, "  ");
        i = i + 1;
    }
}

fn children_count(document: &const TemplateDocument, start: usize, end: usize): usize {
    var count: usize = 0;
    var cursor = start;
    while cursor < end {
        count = count + 1;
        cursor = document.nodes[cursor].subtree_end;
    }
    return count;
}

fn directive(source: []const u8, entry: &const TemplateDirective, depth: usize, out: &List<u8>): void {
    indent(out, depth);
    switch entry.payload {
        .if_expr(span) => {
            const expression = text(source, span);
            append(out, $"directive if=\"{expression}\"\n");
        }
        .else_branch => {
            append(out, "directive else\n");
        }
        .for_expr(loop) => {
            const item = text(source, loop.item_name);
            const iterable = text(source, loop.iterable_expr);
            append(out, $"directive for {item} in {iterable}\n");
        }
        .event(event) => {
            const name = text(source, event.name);
            const expression = text(source, event.expression);
            append(out, $"directive on:{name}=\"{expression}\"\n");
        }
        .bind(bind) => {
            const name = text(source, bind.name);
            const expression = text(source, bind.expression);
            append(out, $"directive bind:{name}=\"{expression}\"\n");
        }
        .slot_assign(name_span) => {
            const name = text(source, name_span);
            append(out, $"directive slot:{name} [{entry.span.start}..{entry.span.end}]\n");
        }
    }
}

fn nodes(
    source: []const u8,
    document: &const TemplateDocument,
    start: usize,
    end: usize,
    depth: usize,
    out: &List<u8>
): void {
    var cursor = start;
    while cursor < end {
        const node = &document.nodes[cursor];
        indent(out, depth);
        switch node.payload {
            .text(span) => {
                const value = text(source, span);
                append(out, $"text `{value}` [{span.start}..{span.end}]\n");
            }
            .interpolation(span) => {
                const expression = text(source, span);
                append(out, $"interpolation `{expression}` [{node.span.start}..{node.span.end}]\n");
            }
            .slot_outlet(value) => {
                if value.name is span {
                    const name = text(source, span);
                    append(out, $"slot name=\"{name}\" [{node.span.start}..{node.span.end}]\n");
                } else {
                    append(out, $"slot <default> [{node.span.start}..{node.span.end}]\n");
                }
                nodes(source, document, cursor + 1, node.subtree_end, depth + 1, out);
            }
            .element(value) => {
                const tag = text(source, value.tag_name);
                const child_count = children_count(document, cursor + 1, node.subtree_end);
                append(out, $"element <{tag}> attrs={value.attributes_count} directives={value.directives_count} children={child_count} [{node.span.start}..{node.span.end}]\n");
                var attribute_index = value.attributes_start;
                const attribute_end = value.attributes_start + value.attributes_count;
                while attribute_index < attribute_end {
                    const attribute = &document.attributes[attribute_index];
                    indent(out, depth + 1);
                    const name = text(source, attribute.name);
                    if attribute.value is value_span {
                        const attribute_value = text(source, value_span);
                        append(out, $"attr {name}=\"{attribute_value}\" [{attribute.span.start}..{attribute.span.end}]\n");
                    } else {
                        append(out, $"attr {name} [{attribute.span.start}..{attribute.span.end}]\n");
                    }
                    attribute_index = attribute_index + 1;
                }
                var directive_index = value.directives_start;
                const directive_end = value.directives_start + value.directives_count;
                while directive_index < directive_end {
                    directive(source, &document.directives[directive_index], depth + 1, out);
                    directive_index = directive_index + 1;
                }
                nodes(source, document, cursor + 1, node.subtree_end, depth + 1, out);
            }
        }
        cursor = node.subtree_end;
    }
}

pub fn format(source: string, document: &const TemplateDocument, sfc: &const SfcDocument, source_path: string): string {
    var out = list<u8>();
    const bytes = source.bytes();
    append(&out, $"AST source={source_path}\n");
    append(&out, "sfc\n");
    append(&out, $"  template content=[{sfc.template.content_span.start}..{sfc.template.content_span.end}]\n");
    append(&out, $"  script content=[{sfc.script.content_span.start}..{sfc.script.content_span.end}]\n");
    if sfc.style is section {
        append(&out, $"  style content=[{section.content_span.start}..{section.content_span.end}]\n");
    } else {
        append(&out, "  style <none>\n");
    }
    const root_count = children_count(document, 0, document.nodes.len());
    append(&out, $"template-ast roots={root_count}\n");
    nodes(bytes[sfc.template.content_span.start..sfc.template.content_span.end], document, 0, root_count, 1, &out);
    return string.from(out.view());
}
