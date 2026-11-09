// Operation: retained target-neutral LIR -> reference text inspection.
import { LirDocument, LirDirectiveEffect } from .compiler.lower.lir;
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

fn effects(source: []const u8, entries: &const List<LirDirectiveEffect>, depth: usize, out: &List<u8>): void {
    var i: usize = 0;
    while i < entries.len() {
        indent(out, depth);
        const entry = &entries[i];
        switch entry {
            .event(value) => {
                const name = text(source, value.name);
                const expression = text(source, value.expression);
                append(out, $"event {name} -> {expression}\n");
            }
            .bind(value) => {
                const name = text(source, value.name);
                const expression = text(source, value.expression);
                append(out, $"bind {name} <- {expression}\n");
            }
        }
        i = i + 1;
    }
}

fn nodes(source: []const u8, document: &const LirDocument, ids: &const List<usize>, depth: usize, out: &List<u8>): void {
    var i: usize = 0;
    while i < ids.len() {
        const node = &document.nodes[ids[i]];
        indent(out, depth);
        switch node.payload {
            .text(span) => {
                const value = text(source, span);
                append(out, $"text `{value}`\n");
            }
            .interpolation(span) => {
                const value = text(source, span);
                append(out, $"interpolation `{value}`\n");
            }
            .element(element) => {
                const tag = text(source, element.tag_name);
                append(out, $"element <{tag}>\n");
                var a: usize = 0;
                while a < element.attributes.len() {
                    const attribute = &element.attributes[a];
                    indent(out, depth + 1);
                    const name = text(source, attribute.name);
                    if attribute.value is span {
                        const value = text(source, span);
                        append(out, $"attr {name}=\"{value}\"\n");
                    } else {
                        append(out, $"attr {name}\n");
                    }
                    a = a + 1;
                }
                effects(source, &element.effects, depth + 1, out);
                nodes(source, document, &element.children, depth + 1, out);
            }
            .conditional(value) => {
                const condition = text(source, value.condition);
                append(out, $"conditional if=\"{condition}\"\n");
                indent(out, depth + 1);
                append(out, "consequent\n");
                nodes(source, document, &value.consequent, depth + 2, out);
                if value.alternate.len() > 0 {
                    indent(out, depth + 1);
                    append(out, "alternate\n");
                    nodes(source, document, &value.alternate, depth + 2, out);
                }
            }
            .for_loop(value) => {
                const item = text(source, value.item_name);
                const iterable = text(source, value.iterable_expr);
                append(out, $"for {item} in {iterable}\n");
                nodes(source, document, &value.body, depth + 1, out);
            }
            .component(value) => {
                const tag = text(source, value.tag_name);
                append(out, $"component <{tag}>\n");
                effects(source, &value.effects, depth + 1, out);
                var s: usize = 0;
                while s < value.slot_provisions.len() {
                    const provision = &value.slot_provisions[s];
                    indent(out, depth + 1);
                    if provision.name is span {
                        const name = text(source, span);
                        append(out, $"slot provision {name}\n");
                    } else {
                        append(out, "slot provision <default>\n");
                    }
                    nodes(source, document, &provision.children, depth + 2, out);
                    s = s + 1;
                }
            }
            .slot_outlet(value) => {
                if value.name is span {
                    const name = text(source, span);
                    append(out, $"slot name=\"{name}\"\n");
                } else {
                    append(out, "slot <default>\n");
                }
                nodes(source, document, &value.fallback_children, depth + 1, out);
            }
        }
        i = i + 1;
    }
}

pub fn format(source: string, document: &const LirDocument): string {
    var out = list<u8>();
    append(&out, "LIR\n");
    nodes(source.bytes(), document, &document.roots, 1, &out);
    return string.from(out.view());
}
