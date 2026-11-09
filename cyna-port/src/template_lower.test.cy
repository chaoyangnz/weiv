import { parse } from .compiler.parser.template.parse;
import { normalize } from .compiler.parser.template.normalize;
import { bind } from .compiler.sema.bind_template;
import { lower, LowerError } from .compiler.lower.lower_template;
import { LirDocument } from .compiler.lower.lir;
import { ScriptFacts, ScriptBinding, ScriptImport, ScriptDiagnostic, HelperFacts, MutationFacts, AliasFacts, CallbackRegistrationFacts } from .compiler.sema.script_facts;
import { ComponentManifests, ComponentSlotManifest } from .compiler.sema.component_manifests;
import { text } from .compiler.sema.binding_context;

fn script_with(names: []const string): ScriptFacts {
    var bindings = list<ScriptBinding>();
    for name in names {
        bindings.push(ScriptBinding {
            name: name,
            kind: "immutable",
            exported: false,
            template_visible: true,
            callable: true,
            type_annotation: none,
            span: {
                start: 0,
                end: 0
            }
        });
    }
    return {
        ok: true,
        source_path: "test.ts",
        props: none,
        bindings: bindings,
        imports: list<ScriptImport>(),
        diagnostics: list<ScriptDiagnostic>(),
        state_facts: {
            helpers: list<HelperFacts>(),
            mutations: list<MutationFacts>(),
            aliases: list<AliasFacts>(),
            callback_registrations: list<CallbackRegistrationFacts>()
        }
    };
}
fn lowered(source: string, names: []const string): LirDocument {
    const raw = parse(source.bytes()) catch (code) {
        panic("Expected parse");
    };
    const normalized = normalize(&raw) catch (code) {
        panic("Expected normalization");
    };
    const script = script_with(names);
    const catalogs: ComponentManifests = {
        entries: list<ComponentSlotManifest>()
    };
    const bindings = bind(source.bytes(), &raw, &normalized, &script, &catalogs);
    return lower(source.bytes(), &raw, &normalized, &bindings) catch (code) {
        panic("Expected lowering");
    };
}
fn basic(source: string): LirDocument {
    const names: [0]string = [];
    return lowered(source, names[..0]);
}
fn expect_error(source: string, expected: LowerError): void {
    const raw = parse(source.bytes()) catch (code) {
        panic("Expected parse");
    };
    const normalized = normalize(&raw) catch (code) {
        panic("Expected normalization");
    };
    const names: [0]string = [];
    const script = script_with(names[..0]);
    const catalogs: ComponentManifests = {
        entries: list<ComponentSlotManifest>()
    };
    const bindings = bind(source.bytes(), &raw, &normalized, &script, &catalogs);
    const output = lower(source.bytes(), &raw, &normalized, &bindings) catch (code) {
        assert(code == expected);
        return;
    };
    assert(false);
}

test "LIR empty source and ordinary elements preserve roots and attributes" {
    const empty = basic("");
    assert(empty.roots.len() == 0);
    assert(empty.nodes.len() == 0);
    const source = "<p id=\"x\" disabled>Hello</p><br>";
    const result = basic(source);
    assert(result.nodes.len() == 3);
    assert(result.roots.len() == 2);
    const payload_0 = &result.nodes[result.roots[0]].payload;
    switch payload_0 {
        .element(element) => {
            assert(text(source.bytes(), element.tag_name) == "p");
            assert(element.attributes.len() == 2);
            assert(element.effects.len() == 0);
            assert(element.children.len() == 1);
            assert(text(source.bytes(), element.attributes[0].name) == "id");
            if element.attributes[0].value is value {
                assert(text(source.bytes(), value) == "x");
            } else {
                assert(false);
            }
            if element.attributes[1].value is value {
                assert(false);
            }
            const payload_1 = &result.nodes[element.children[0]].payload;
            switch payload_1 {
                .text(span) => {
                    assert(text(source.bytes(), span) == "Hello");
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

test "directive effects retain event bind order and drop deprecation metadata" {
    const source = "<p @click=\"go()\" bind:value=\"state\"/>";
    const result = basic(source);
    const payload_2 = &result.nodes[0].payload;
    switch payload_2 {
        .element(element) => {
            assert(element.effects.len() == 2);
            const payload_3 = &element.effects[0];
            switch payload_3 {
                .event(effect) => {
                    assert(text(source.bytes(), effect.name) == "click");
                    assert(text(source.bytes(), effect.expression) == "go()");
                }
                _ => {
                    assert(false);
                }
            }
            const payload_4 = &element.effects[1];
            switch payload_4 {
                .bind(effect) => {
                    assert(text(source.bytes(), effect.name) == "value");
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

test "components discard ordinary attributes and preserve effects" {
    const result = basic("<Card title=\"ignored\" :title=\"value\"/>");
    const payload_5 = &result.nodes[0].payload;
    switch payload_5 {
        .component(component) => {
            assert(component.effects.len() == 1);
            assert(component.slot_provisions.len() == 0);
        }
        _ => {
            assert(false);
        }
    }
}

test "named provisions merge interleaved content by first encounter" {
    const source = "<Card><p slot:head>A</p>first<b slot:head>B</b>last</Card>";
    const result = basic(source);
    const payload_6 = &result.nodes[0].payload;
    switch payload_6 {
        .component(component) => {
            assert(component.slot_provisions.len() == 2);
            const named = &component.slot_provisions[0];
            if named.name is name {
                assert(text(source.bytes(), name) == "head");
            } else {
                assert(false);
            }
            assert(named.children.len() == 2);
            const payload_7 = &result.nodes[named.children[0]].payload;
            switch payload_7 {
                .element(element) => {
                    assert(text(source.bytes(), element.tag_name) == "p");
                    assert(element.effects.len() == 0);
                }
                _ => {
                    assert(false);
                }
            }
            const payload_8 = &result.nodes[named.children[1]].payload;
            switch payload_8 {
                .element(element) => {
                    assert(text(source.bytes(), element.tag_name) == "b");
                }
                _ => {
                    assert(false);
                }
            }
            const defaults = &component.slot_provisions[1];
            if defaults.name is name {
                assert(false);
            }
            assert(defaults.children.len() == 2);
        }
        _ => {
            assert(false);
        }
    }
}

test "template groups flatten their children and discard group attributes and effects" {
    const source = "<Card><template slot:head id=\"ignored\" @click=\"go\"><b/><i/></template><template slot:head><hr/></template></Card>";
    const result = basic(source);
    assert(result.nodes.len() == 4);
    const payload_9 = &result.nodes[0].payload;
    switch payload_9 {
        .component(component) => {
            assert(component.slot_provisions.len() == 1);
            assert(component.slot_provisions[0].children.len() == 3);
        }
        _ => {
            assert(false);
        }
    }
    // Binding facts remain even when the template wrapper's runtime effect is omitted.
    assert(result.expressions.len() == 1);
}

test "empty template projection creates an empty provision" {
    const result = basic("<Card><template slot:head/></Card>");
    assert(result.nodes.len() == 1);
    const payload_10 = &result.nodes[0].payload;
    switch payload_10 {
        .component(component) => {
            assert(component.slot_provisions.len() == 1);
            assert(component.slot_provisions[0].children.len() == 0);
        }
        _ => {
            assert(false);
        }
    }
}

test "default content merges across multiple children" {
    const result = basic("<Card><p/>text<i/></Card>");
    const payload_11 = &result.nodes[0].payload;
    switch payload_11 {
        .component(component) => {
            assert(component.slot_provisions.len() == 1);
            if component.slot_provisions[0].name is name {
                assert(false);
            }
            assert(component.slot_provisions[0].children.len() == 3);
        }
        _ => {
            assert(false);
        }
    }
}

test "first slot assignment selects the provision and all assignments are removed" {
    const source = "<Card><p slot:first slot:second @click=\"go\"/></Card>";
    const result = basic(source);
    const payload_12 = &result.nodes[0].payload;
    switch payload_12 {
        .component(component) => {
            assert(component.slot_provisions.len() == 1);
            if component.slot_provisions[0].name is name {
                assert(text(source.bytes(), name) == "first");
            } else {
                assert(false);
            }
            const child = component.slot_provisions[0].children[0];
            const payload_13 = &result.nodes[child].payload;
            switch payload_13 {
                .element(element) => {
                    assert(element.effects.len() == 1);
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

test "projected child components recursively lower their own provisions" {
    const result = basic("<Outer><Inner slot:head><b slot:body/></Inner></Outer>");
    const payload_14 = &result.nodes[0].payload;
    switch payload_14 {
        .component(outer) => {
            const inner_id = outer.slot_provisions[0].children[0];
            const payload_15 = &result.nodes[inner_id].payload;
            switch payload_15 {
                .component(inner) => {
                    assert(inner.slot_provisions.len() == 1);
                    assert(inner.slot_provisions[0].children.len() == 1);
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

test "conditional loop and slot fallback edges preserve structure" {
    const source = "<p #if=\"ok\"><i #for=\"item in items\">{{item}}</i></p><b #else><slot name=\"head\">fallback</slot></b>";
    const result = basic(source);
    const payload_16 = &result.nodes[result.roots[0]].payload;
    switch payload_16 {
        .conditional(branch) => {
            assert(text(source.bytes(), branch.condition) == "ok");
            assert(branch.consequent.len() == 1);
            assert(branch.alternate.len() == 1);
            const payload_17 = &result.nodes[branch.consequent[0]].payload;
            switch payload_17 {
                .element(element) => {
                    const payload_18 = &result.nodes[element.children[0]].payload;
                    switch payload_18 {
                        .for_loop(loop) => {
                            assert(text(source.bytes(), loop.item_name) == "item");
                            assert(loop.body.len() == 1);
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
            const payload_19 = &result.nodes[branch.alternate[0]].payload;
            switch payload_19 {
                .element(element) => {
                    const payload_20 = &result.nodes[element.children[0]].payload;
                    switch payload_20 {
                        .slot_outlet(outlet) => {
                            if outlet.name is name {
                                assert(text(source.bytes(), name) == "head");
                            } else {
                                assert(false);
                            }
                            assert(outlet.fallback_children.len() == 1);
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
        _ => {
            assert(false);
        }
    }
}

test "slot assignment and template placement are hard lower-stage errors" {
    expect_error("<p slot:head/>", LowerError.invalid_slot_placement);
    expect_error("<div><p slot:head/></div>", LowerError.invalid_slot_placement);
    expect_error("<Card slot:head/>", LowerError.invalid_slot_placement);
    expect_error("<template/>", LowerError.invalid_slot_template_placement);
    expect_error("<template slot:head/>", LowerError.invalid_slot_template_placement);
    expect_error("<Card><template/></Card>", LowerError.invalid_slot_template_placement);
}

test "structural wrappers do not make named projections direct children" {
    expect_error("<Card><p #if=\"ok\" slot:head/></Card>", LowerError.invalid_slot_placement);
    expect_error("<Card><template #if=\"ok\" slot:head/></Card>", LowerError.invalid_slot_template_placement);
    expect_error("<Card><template slot:head><i slot:other/></template></Card>", LowerError.invalid_slot_placement);
}

test "expression lookup uses source identity and copied reference lists" {
    const source = "{{value + value()}}{{value}}";
    const names: [1]string = ["value"];
    const result = lowered(source, names[..1]);
    assert(result.expressions.len() == 2);
    assert(result.expressions[0].references.len() == 1);
    assert(result.expressions[0].references[0].name == "value");
    assert(result.expressions[0].references[0].call);
    if result.find_expression(result.expressions[0].source) is id {
        assert(id == 0);
    } else {
        assert(false);
    }
    if result.find_expression(result.expressions[1].source) is id {
        assert(id == 1);
    } else {
        assert(false);
    }
    if result.find_expression({
        start: 0,
        end: 0
    }) is id {
        assert(false);
    }
    const repeated = lowered("{{value}}{{value}}", names[..1]);
    assert(repeated.expressions.len() == 2);
    if repeated.find_expression(repeated.expressions[0].source) is first {
        assert(first == 0);
    } else {
        assert(false);
    }
    if repeated.find_expression(repeated.expressions[1].source) is second {
        assert(second == 1);
    } else {
        assert(false);
    }

}

test "deep lowering uses flat nodes and nonrecursive edge storage" {
    var source = list<u8>();
    var i: usize = 0;
    while i < 512 {
        for byte in "<a>".bytes() {
            source.push(byte);
        }
        i = i + 1;
    }
    source.push(120);
    i = 0;
    while i < 512 {
        for byte in "</a>".bytes() {
            source.push(byte);
        }
        i = i + 1;
    }
    const result = basic(string.from(source.view()));
    assert(result.nodes.len() == 513);
    assert(result.roots.len() == 1);
}
