// Operation: retained browser render tree -> reference text inspection.
import { RenderDocument } from .compiler.backend.browser.render_tree.tree;
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

fn nodes(source: []const u8, document: &const RenderDocument, ids: &const List<usize>, depth: usize, out: &List<u8>): void {
    var i: usize = 0;
    while i < ids.len() {
        const node = &document.nodes[ids[i]];
        indent(out, depth);
        switch node.payload {
            .text(span) => {
                const value = text(source, span);
                append(out, $"text {value}\n");
            }
            .interpolation(value) => {
                const expression = text(source, value.expression);
                append(out, $"interpolation ref={value.ref_id} expr={expression}\n");
            }
            .element(value) => {
                const tag = text(source, value.tag_name);
                const attrs = value.attributes.len();
                const binds = value.bind_effects.len();
                const events = value.event_effects.len();
                append(out, $"element ref={value.ref_id} <{tag}> attrs={attrs} binds={binds} events={events}\n");
                nodes(source, document, &value.children, depth + 1, out);
            }
            .conditional(value) => {
                const condition = text(source, value.condition);
                append(out, $"conditional refs=[{value.start_ref_id},{value.end_ref_id}] state={value.state_ref_id} if={condition}\n");
                indent(out, depth + 1);
                append(out, "consequent\n");
                nodes(source, document, &value.consequent, depth + 2, out);
                indent(out, depth + 1);
                append(out, "alternate\n");
                nodes(source, document, &value.alternate, depth + 2, out);
            }
            .for_loop(value) => {
                const item = text(source, value.item_name);
                const iterable = text(source, value.iterable_expr);
                append(out, $"for-loop refs=[{value.start_ref_id},{value.end_ref_id}] state={value.state_ref_id} item={item} in={iterable}\n");
                nodes(source, document, &value.body, depth + 1, out);
            }
            .component(value) => {
                const tag = text(source, value.tag_name);
                const binds = value.bind_effects.len();
                const events = value.event_effects.len();
                const slots = value.slot_provisions.len();
                append(out, $"component refs=[{value.start_ref_id},{value.end_ref_id}] handle={value.handle_ref_id} <{tag}> binds={binds} events={events} slots={slots}\n");
                var s: usize = 0;
                while s < slots {
                    const provision = &value.slot_provisions[s];
                    indent(out, depth + 1);
                    if provision.name is span {
                        const name = text(source, span);
                        append(out, $"slot-provision name={name}\n");
                    } else {
                        append(out, "slot-provision name=default\n");
                    }
                    nodes(source, document, &provision.children, depth + 2, out);
                    s = s + 1;
                }
            }
            .slot_outlet(value) => {
                append(out, $"slot-outlet refs=[{value.start_ref_id},{value.end_ref_id}] handle={value.handle_ref_id} name=");
                if value.name is span {
                    const name = text(source, span);
                    append(out, $"{name}\n");
                } else {
                    append(out, "default\n");
                }
                nodes(source, document, &value.fallback_children, depth + 1, out);
            }
        }
        i = i + 1;
    }
}

pub fn format(source: string, document: &const RenderDocument): string {
    var out = list<u8>();
    append(&out, $"render-tree next_ref_id={document.next_ref_id}\n");
    nodes(source.bytes(), document, &document.roots, 0, &out);
    return string.from(out.view());
}
