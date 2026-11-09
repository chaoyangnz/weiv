import { parse } from .compiler.parser.template.parse;
import { normalize } from .compiler.parser.template.normalize;
import { lower as lower_lir } from .compiler.lower.lower_template;
import { LirDocument, LirNode } from .compiler.lower.lir;
import { TemplateBindings, ComponentRef, ExpressionFacts, TemplateBindingDiagnostic } from .compiler.sema.template_bindings;
import { SlotManifest, SlotEntry } from .compiler.sema.slot_manifest;
import { RenderDocument } from .compiler.backend.browser.render_tree.tree;
import { lower } from .compiler.backend.browser.render_tree.lower;
import { text } from .compiler.sema.binding_context;

fn lir(source: string): LirDocument {
    const raw = parse(source.bytes()) catch (code) {
        panic("Expected raw template");
    };
    const normalized = normalize(&raw) catch (code) {
        panic("Expected normalized template");
    };
    const bindings: TemplateBindings = {
        component_refs: list<ComponentRef>(),
        expressions: list<ExpressionFacts>(),
        diagnostics: list<TemplateBindingDiagnostic>(),
        own_slot_manifest: SlotManifest {
            entries: list<SlotEntry>()
        }
    };
    return lower_lir(source.bytes(), &raw, &normalized, &bindings) catch (code) {
        panic("Expected LIR");
    };
}
fn render(source: string): RenderDocument {
    const document = lir(source);
    return lower(&document);
}
fn first_ref(document: &const RenderDocument, id: usize): usize {
    const payload = &document.nodes[id].payload;
    return switch payload {
        .element(value) => value.ref_id;
        .interpolation(value) => value.ref_id;
        .conditional(value) => value.start_ref_id;
        .for_loop(value) => value.start_ref_id;
        .component(value) => value.start_ref_id;
        .slot_outlet(value) => value.start_ref_id;
        .text(value) => {
            panic("Text allocates no reference");
        }
    };
}

test "empty and text-only render trees allocate no references" {
    const empty = render("");
    assert(empty.nodes.len() == 0);
    assert(empty.roots.len() == 0);
    assert(empty.next_ref_id == 0);
    const text_only = render("Hello 🌱");
    assert(text_only.nodes.len() == 1);
    assert(text_only.roots.len() == 1);
    assert(text_only.next_ref_id == 0);
    const payload = &text_only.nodes[0].payload;
    switch payload {
        .text(span) => {
            assert(text("Hello 🌱".bytes(), span) == "Hello 🌱");
        }
        _ => {
            assert(false);
        }
    }
}

test "elements allocate references after children and roots retain logical order" {
    const source = "<div><b/>{{x}}</div><i/>";
    const result = render(source);
    assert(result.nodes.len() == 4);
    assert(result.roots.len() == 2);
    assert(result.roots[0] == 0);
    assert(result.roots[1] == 3);
    assert(first_ref(&result, 0) == 2);
    assert(first_ref(&result, 1) == 0);
    assert(first_ref(&result, 2) == 1);
    assert(first_ref(&result, 3) == 3);
    assert(result.next_ref_id == 4);
    assert(result.nodes[0].span.start == 0);
    assert(text(source.bytes(), result.nodes[2].span) == "{{x}}");
}

test "conditional anchors precede both branches while element refs follow their children" {
    const result = render("<p #if=\"ok\">{{x}}</p><b #else/>");
    assert(result.next_ref_id == 6);
    assert(first_ref(&result, 0) == 0);
    assert(first_ref(&result, 1) == 4);
    assert(first_ref(&result, 2) == 3);
    assert(first_ref(&result, 3) == 5);
    const payload = &result.nodes[0].payload;
    switch payload {
        .conditional(value) => {
            assert(value.end_ref_id == 1);
            assert(value.state_ref_id == 2);
            assert(value.consequent[0] == 1);
            assert(value.alternate[0] == 3);
        }
        _ => {
            assert(false);
        }
    }
}

test "loop anchors and state precede body references" {
    const result = render("<i #for=\"item in items\">{{item}}</i>");
    assert(result.next_ref_id == 5);
    assert(first_ref(&result, 0) == 0);
    assert(first_ref(&result, 1) == 4);
    assert(first_ref(&result, 2) == 3);
    const payload = &result.nodes[0].payload;
    switch payload {
        .for_loop(value) => {
            assert(value.end_ref_id == 1);
            assert(value.state_ref_id == 2);
            assert(value.body[0] == 1);
        }
        _ => {
            assert(false);
        }
    }
}

test "slot outlet anchors and handle precede fallback references" {
    const source = "<slot name=\"head\"><b/>{{x}}</slot>";
    const result = render(source);
    assert(result.next_ref_id == 5);
    assert(first_ref(&result, 0) == 0);
    assert(first_ref(&result, 1) == 3);
    assert(first_ref(&result, 2) == 4);
    const payload = &result.nodes[0].payload;
    switch payload {
        .slot_outlet(value) => {
            assert(value.end_ref_id == 1);
            assert(value.handle_ref_id == 2);
            assert(value.fallback_children.len() == 2);
            if value.name is name {
                assert(text(source.bytes(), name) == "head");
            } else {
                assert(false);
            }
        }
        _ => {
            assert(false);
        }
    }
    const unnamed = render("<slot/>");
    const unnamed_payload = &unnamed.nodes[0].payload;
    switch unnamed_payload {
        .slot_outlet(value) => {
            if value.name is name {
                assert(false);
            }
            assert(value.fallback_children.len() == 0);
        }
        _ => {
            assert(false);
        }
    }
}

test "component anchors and handle follow all projected children" {
    const result = render("<Card><b/>{{x}}</Card>");
    assert(result.next_ref_id == 5);
    assert(first_ref(&result, 1) == 0);
    assert(first_ref(&result, 2) == 1);
    assert(first_ref(&result, 0) == 2);
    const payload = &result.nodes[0].payload;
    switch payload {
        .component(value) => {
            assert(value.end_ref_id == 3);
            assert(value.handle_ref_id == 4);
        }
        _ => {
            assert(false);
        }
    }
}

test "merged provisions drive reference order rather than source arena order" {
    const result = render("<Card><b slot:head/>{{x}}<i slot:head/></Card>");
    assert(result.next_ref_id == 6);
    assert(first_ref(&result, 1) == 0);
    assert(first_ref(&result, 3) == 1);
    assert(first_ref(&result, 2) == 2);
    assert(first_ref(&result, 0) == 3);
    const payload = &result.nodes[0].payload;
    switch payload {
        .component(value) => {
            assert(value.slot_provisions.len() == 2);
            const named = &value.slot_provisions[0];
            const defaults = &value.slot_provisions[1];
            assert(named.children[0] == 1);
            assert(named.children[1] == 3);
            assert(defaults.children[0] == 2);
        }
        _ => {
            assert(false);
        }
    }
}

test "flattened template groups add no browser nodes or references" {
    const result = render("<Card><template slot:head><b/></template>text</Card>");
    assert(result.nodes.len() == 3);
    assert(result.next_ref_id == 4);
    assert(first_ref(&result, 1) == 0);
    assert(first_ref(&result, 0) == 1);
}

test "element effects split stably and retain attributes after LIR destruction" {
    const source = "<p @click=\"a\" bind:title=\"one\" @change=\"b\" :value=\"two\" disabled/>";
    const result = render(source);
    const payload = &result.nodes[0].payload;
    switch payload {
        .element(value) => {
            assert(value.bind_effects.len() == 2);
            assert(value.event_effects.len() == 2);
            assert(value.attributes.len() == 1);
            assert(text(source.bytes(), value.attributes[0].name) == "disabled");
            if value.attributes[0].value is content {
                assert(false);
            }
            const bind0 = &value.bind_effects[0];
            const bind1 = &value.bind_effects[1];
            const event0 = &value.event_effects[0];
            const event1 = &value.event_effects[1];
            switch bind0 {
                .bind(effect) => {
                    assert(text(source.bytes(), effect.name) == "title");
                    assert(text(source.bytes(), effect.expression) == "one");
                }
                _ => {
                    assert(false);
                }
            }
            switch bind1 {
                .bind(effect) => {
                    assert(text(source.bytes(), effect.name) == "value");
                }
                _ => {
                    assert(false);
                }
            }
            switch event0 {
                .event(effect) => {
                    assert(text(source.bytes(), effect.name) == "click");
                }
                _ => {
                    assert(false);
                }
            }
            switch event1 {
                .event(effect) => {
                    assert(text(source.bytes(), effect.name) == "change");
                }
                _ => {
                    assert(false);
                }
            }
        }
        _ => {
            assert(false);
        }
    }
}

test "component effects split independently and ordinary component attributes stay omitted" {
    const result = render("<Card ignored=\"yes\" @pick=\"save\" bind:title=\"title\"/>");
    assert(result.next_ref_id == 3);
    const payload = &result.nodes[0].payload;
    switch payload {
        .component(value) => {
            assert(value.bind_effects.len() == 1);
            assert(value.event_effects.len() == 1);
            assert(value.slot_provisions.len() == 0);
        }
        _ => {
            assert(false);
        }
    }
}

test "render collections survive replacing and dropping original LIR owners" {
    const source = "<p id=\"kept\" @click=\"save\"><b/></p>";
    var document = lir(source);
    const result = lower(&document);
    document.nodes[0] = LirNode {
        span: {
            start: 0,
            end: 0
        },
        payload: .text({
            start: 0,
            end: 0
        })
    };
    document.roots = list<usize>();
    const payload = &result.nodes[0].payload;
    switch payload {
        .element(value) => {
            assert(value.children[0] == 1);
            assert(value.event_effects.len() == 1);
            assert(value.attributes.len() == 1);
            if value.attributes[0].value is content {
                assert(text(source.bytes(), content) == "kept");
            } else {
                assert(false);
            }
        }
        _ => {
            assert(false);
        }
    }
    assert(result.roots[0] == 0);
    assert(result.next_ref_id == 2);
}

test "lowering repeats deterministically and traverses deep trees without recursion" {
    var bytes = list<u8>();
    var i: usize = 0;
    while i < 512 {
        for byte in "<a>".bytes() {
            bytes.push(byte);
        }
        i = i + 1;
    }
    for byte in "{{x}}".bytes() {
        bytes.push(byte);
    }
    i = 0;
    while i < 512 {
        for byte in "</a>".bytes() {
            bytes.push(byte);
        }
        i = i + 1;
    }
    const document = lir(string.from(bytes.view()));
    const first = lower(&document);
    const second = lower(&document);
    assert(first.nodes.len() == 513);
    assert(first.next_ref_id == 513);
    assert(second.next_ref_id == 513);
    assert(first_ref(&first, 0) == 512);
    assert(first_ref(&first, 512) == 0);
    assert(first_ref(&second, 0) == 512);
    assert(first_ref(&second, 512) == 0);
}
