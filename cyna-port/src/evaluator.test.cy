import std.mem;
import { build, EvaluatorError } from .compiler.backend.browser.emit.build_evaluator_plan;
import { EvaluatorPlan, EvaluatorSite, EvaluatorArgument } from .compiler.backend.browser.emit.evaluator_plan;
import { emit as emit_call } from .compiler.backend.browser.emit.js_module.emit_evaluator_call;
import { emit, emit_with_selection, emit_with_local_state } from .compiler.backend.browser.emit.emit_module;
import { CellSelection, LocalSubscription, ManagedSubscription } from .compiler.backend.browser.emit.cell_selection;
import { empty } from .compiler.backend.browser.emit.cell_selection;
import { select_into } from .compiler.backend.browser.emit.select_local_state;
import { JavaScriptModule, ImportOverride } from .compiler.backend.browser.emit.javascript_module;
import { JavaScriptError } from .compiler.backend.browser.emit.javascript_errors;
import { compile_report, take_unit } from .compiler.compile;
import { build as browser_build } from .compiler.backend.browser.build_component;
import { BrowserComponent } from .compiler.backend.browser.component;
import { ComponentManifests, ComponentSlotManifest } from .compiler.sema.component_manifests;
import { expression_supported, ScriptBackendError } from .ffi.script_backend;
fn browser(template: string, extra: string): BrowserComponent {
    const script = $"export interface Props \{ title?: string; \} export let props: Props; export let value=1; export const items=[1,2]; export const Card=\{\}; export function save(value) \{ return value; \} {extra}";
    const source = $"<template>{template}</template><script lang=\"ts\">{script}</script>";
    const catalogs: ComponentManifests = {
        entries: list<ComponentSlotManifest>()
    };
    var report = compile_report(source, "evaluators.weiv", &catalogs);
    const unit = take_unit(&report) catch (code) {
        panic("Expected unit");
    };
    return browser_build(unit);
}
fn plan(template: string, extra: string): EvaluatorPlan {
    const component = browser(template, extra);
    const span = component.unit.sfc_document.template.content_span;
    const bytes = component.unit.source.bytes();
    return build(bytes[span.start..span.end], &component.render_tree, &component.unit.script.facts) catch (code) {
        panic("Expected plan");
    };
}
fn compiled_module(template: string): JavaScriptModule {
    const component = browser(template, "");
    const overrides = list<ImportOverride>();
    return emit(&component, &overrides) catch (code) {
        panic("Expected module");
    };
}
fn helper_position(source: []const u8, needle: []const u8): usize {
    var offset: usize = 0;
    while offset + needle.len() <= source.len() {
        var matches = true;
        var index: usize = 0;
        while index < needle.len() {
            if source[offset + index] != needle[index] {
                matches = false;
            }
            index = index + 1;
        }
        if matches {
            return offset;
        }
        offset = offset + 1;
    }
    panic("Expected update helper");
}
fn rejected(template: string, expected: EvaluatorError): void {
    const component = browser(template, "");
    const span = component.unit.sfc_document.template.content_span;
    const bytes = component.unit.source.bytes();
    const result = build(bytes[span.start..span.end], &component.render_tree, &component.unit.script.facts) catch (code) {
        assert(code == expected);
        return;
    };
    assert(false);
}
test "evaluator plan retains logical order bindings then handlers then descendants" {
    const output = plan("<p @click=\"save\" bind:title=\"value\">{{props.title}}</p>", "");
    assert(output.records.len() == 3);
    assert(output.records[0].site == EvaluatorSite.binding);
    assert(output.records[1].site == EvaluatorSite.handler);
    assert(output.records[1].argument == EvaluatorArgument.event);
    assert(output.records[2].site == EvaluatorSite.interpolation);
    assert(output.records[2].id == 2);
    const found = EvaluatorPlan.find(&output, 0, EvaluatorSite.binding, 0);
    if found is index {
        assert(index == 0);
    } else {
        assert(false);
    }
    const missing = EvaluatorPlan.find(&output, 0, EvaluatorSite.binding, 9);
    if missing is none {} else {
        assert(false);
    }

}
test "loop iterable is outside its local scope and nested shadowing emits one local declaration" {
    const output = plan("<i #for=\"item in items\">{{item}}<b #for=\"item in items\">{{item}}</b></i>{{value}}", "");
    assert(output.records.len() == 5);
    assert(output.records[0].site == EvaluatorSite.iterable);
    assert(mem.contains(output.code.bytes(), "const item=__weiv_context[\"item\"];".bytes()));
    const record = &output.records[4];
    const bytes = output.code.bytes();
    assert(string.from(bytes[record.generated.start..record.generated.end]) == "value");
}
test "component payload handlers precede projected slots and outlets include fallback" {
    const output = plan("<Card @saved=\"save\" bind:value=\"value\"><p>{{value}}</p></Card><slot>{{props.title}}</slot>", "");
    assert(output.records.len() == 4);
    assert(output.records[1].argument == EvaluatorArgument.payload);
    assert(output.records[2].site == EvaluatorSite.interpolation);
    assert(output.records[3].site == EvaluatorSite.interpolation);
}
test "conditional consequent and alternate keep lexical evaluator order" {
    const output = plan("<p #if=\"value\">{{1}}</p><p #else>{{2}}</p>", "");
    assert(output.records.len() == 3);
    assert(output.records[0].site == EvaluatorSite.condition);
    const bytes = output.code.bytes();
    assert(string.from(bytes[output.records[1].generated.start..output.records[1].generated.end]) == "1");
    assert(string.from(bytes[output.records[2].generated.start..output.records[2].generated.end]) == "2");
}
test "every generated range maps exactly back to the original template expression" {
    const component = browser("<p bind:title=\"props.title\">{{ value + 1 }}</p>", "");
    const bytes = component.unit.source.bytes();
    const span = component.unit.sfc_document.template.content_span;
    const source = bytes[span.start..span.end];
    const output = build(source, &component.render_tree, &component.unit.script.facts) catch (code) {
        panic("Expected plan");
    };
    var i: usize = 0;
    while i<output.records.len() {
        const record = &output.records[i];
        const generated = output.code.bytes();
        assert(string.from(source[record.template.start..record.template.end]) == string.from(generated[record.generated.start..record.generated.end]));
        i = i + 1;
    }
    switch component.render_tree.nodes[0].payload {
        .element(value) => {
            assert(value.bind_effects.len() == 1);
        }
        _ => {
            assert(false);
        }
    }
}
test "render mutations and malformed handlers have distinct typed errors" {
    rejected("{{value++}}", EvaluatorError.unsupported_render_expression);
    rejected("<p @click=\"value +\"/>", EvaluatorError.unsupported_handler_expression);
}
test "reserved loop locals remain explicit evaluator errors" {
    rejected("<p #for=\"__weiv_item in items\">{{1}}</p>", EvaluatorError.reserved_identifier);
}
test "evaluator call carries typed render event and payload arguments" {
    const output = plan("<p @click=\"save\">{{value}}</p><Card @saved=\"save\"/>", "");
    assert(emit_call(&output.records[0], "instance.refresh()") == "((__weiv_context) => __weiv_context.__weiv_eval[0](__weiv_context, event))(instance.refresh())");
    assert(emit_call(&output.records[1], "scope") == "((__weiv_context) => __weiv_context.__weiv_eval[1](__weiv_context))(scope)");
    assert(emit_call(&output.records[2], "scope") == "((__weiv_context) => __weiv_context.__weiv_eval[2](__weiv_context, payload))(scope)");
}
test "static templates have empty evaluator code and no records" {
    const output = plan("<p>static</p>", "");
    assert(output.code == "");
    assert(output.records.len() == 0);
}
test "Rust render expression predicate rejects NUL before foreign transport" {
    const bytes: [1]u8 = [0];
    const result = expression_supported(string.from(bytes[..1])) catch (code) {
        assert(code == ScriptBackendError.embedded_nul);
        return;
    };
    assert(false);
}
test "flat module includes lexical evaluators text updates binding updates and events" {
    const output = compiled_module("<button @click=\"save\" bind:title=\"value\">{{value}}</button>");
    assert(mem.contains(output.code.bytes(), "__weiv_scope.__weiv_eval = __weiv_templateExpressions;".bytes()));
    assert(mem.contains(output.code.bytes(), "function updateRegion_text_0".bytes()));
    assert(mem.contains(output.code.bytes(), "function updateRegion_attribute_1_title".bytes()));
    assert(mem.contains(output.code.bytes(), "addEventListener(\"click\"".bytes()));
    assert(mem.contains(output.code.bytes(), "dirtyRegionSet.has(1)".bytes()));
}
test "projected conditional slot owns branch lifecycle" {
    const component = browser("<Card><p #if=\"value\">nested</p></Card>", "");
    const overrides = list<ImportOverride>();
    const output = emit(&component, &overrides) catch (code) {
        panic("Expected projected conditional module");
    };
    assert(mem.contains(output.code.bytes(), "function mountProjectedSlot_".bytes()));
    assert(mem.contains(output.code.bytes(), "function destroyConditionalBranch_".bytes()));
    assert(mem.contains(output.code.bytes(), "function updateRegion_conditional_".bytes()));
}

test "projected default slot emits parent scope mount and child slot map" {
    const component = browser("<Card><p>{{value}}</p></Card>", "");
    const overrides = list<ImportOverride>();
    const output = emit(&component, &overrides) catch (code) {
        panic("Expected projected slot module");
    };
    assert(mem.contains(output.code.bytes(), "function mountProjectedSlot_".bytes()));
    assert(mem.contains(output.code.bytes(), "default: { mountIntoBoundary".bytes()));
    assert(mem.contains(output.code.bytes(), ".setSlots(".bytes()));
}

test "component update helpers follow interleaved render preorder" {
    const output = compiled_module("{{value}}<Card bind:title=\"value\"/>{{value}}<Card><p>{{value}}</p></Card>");
    const code = output.code.bytes();
    const text = helper_position(code, "function updateRegion_text_0".bytes());
    const first_child = helper_position(code, "function updateRegion_child_3".bytes());
    const second_text = helper_position(code, "function updateRegion_text_4".bytes());
    const second_child = helper_position(code, "function updateRegion_child_9".bytes());
    assert(text < first_child);
    assert(first_child < second_text);
    assert(second_text < second_child);
}

test "named projected slot retains its slot key" {
    const component = browser("<Card><template slot:header><h2>{{value}}</h2></template></Card>", "");
    const overrides = list<ImportOverride>();
    const output = emit(&component, &overrides) catch (code) {
        panic("Expected named projected slot module");
    };
    assert(mem.contains(output.code.bytes(), "\"header\": { mountIntoBoundary".bytes()));
}

test "slot outlet emits fallback and supplied slot switching" {
    const component = browser("<slot><p>{{value}}</p></slot>", "");
    const overrides = list<ImportOverride>();
    const output = emit(&component, &overrides) catch (code) {
        panic("Expected slot outlet module");
    };
    assert(mem.contains(output.code.bytes(), "function createSlotFallbackFragment_".bytes()));
    assert(mem.contains(output.code.bytes(), "function updateRegion_slot_".bytes()));
    assert(mem.contains(output.code.bytes(), "instance.slots?.default".bytes()));
    assert(mem.contains(output.code.bytes(), "const __next_slot_".bytes()));
    assert(mem.contains(output.code.bytes(), "const __current_slot_".bytes()));
    assert(mem.contains(output.code.bytes(), "mountIntoBoundary".bytes()));
}

test "child component emits boundary mount props callbacks update and destroy" {
    const component = browser("<Card bind:title=\"props.title\" @saved=\"emit('saved', payload)\"/>", "");
    const overrides = list<ImportOverride>();
    const output = emit(&component, &overrides) catch (code) {
        panic("Expected child component module");
    };
    assert(mem.contains(output.code.bytes(), "component:start".bytes()));
    assert(mem.contains(output.code.bytes(), "Card.mountIntoBoundary".bytes()));
    assert(mem.contains(output.code.bytes(), "function updateRegion_child_".bytes()));
    assert(mem.contains(output.code.bytes(), ".setProps(".bytes()));
    assert(mem.contains(output.code.bytes(), ".setEventHandlers(".bytes()));
    assert(mem.contains(output.code.bytes(), ".destroy();".bytes()));
}

test "keyed loop body emits item scope boundaries and region update" {
    const component = browser("<p #for=\"item in items\">{{item}}</p>", "");
    const overrides = list<ImportOverride>();
    const output = emit(&component, &overrides) catch (code) {
        panic("Expected loop module");
    };
    assert(mem.contains(output.code.bytes(), "function createForEntry_".bytes()));
    assert(mem.contains(output.code.bytes(), "function updateForLoop_".bytes()));
    assert(mem.contains(output.code.bytes(), "moveBoundaryBefore(record.start, record.end".bytes()));
    assert(mem.contains(output.code.bytes(), "const entryRefs = []".bytes()));
}

test "conditional fixed branches emit boundary and dirty region lifecycle" {
    const component = browser("<p #if=\"props.title\">yes</p><p #else>no</p>", "");
    const overrides = list<ImportOverride>();
    const output = emit(&component, &overrides) catch (code) {
        panic("Expected conditional module");
    };
    assert(mem.contains(output.code.bytes(), "function createConditionalFragment_".bytes()));
    assert(mem.contains(output.code.bytes(), "function updateRegion_conditional_".bytes()));
    assert(mem.contains(output.code.bytes(), "replaceBetween(refs[".bytes()));
    assert(mem.contains(output.code.bytes(), "dirtySet.has(\"props\")".bytes()));
}

test "conditional branch interpolation and bindings update under parent region" {
    const component = browser("<p #if=\"props.title\" bind:title=\"value\">{{value}}</p><p #else>{{props.title}}</p>", "");
    const overrides = list<ImportOverride>();
    const output = emit(&component, &overrides) catch (code) {
        panic("Expected dynamic conditional module");
    };
    assert(mem.contains(output.code.bytes(), "function updateRegion_conditional_".bytes()));
    assert(mem.contains(output.code.bytes(), "__next_text_".bytes()));
    assert(mem.contains(output.code.bytes(), "__value_".bytes()));
    assert(component.region_graph.regions.len() == 1);
}

test "conditional event writes need selected local state" {
    const component = browser("<section><button @click=\"toggleOpen\">Toggle</button><p #if=\"open\">open</p><p #else>closed</p></section>", "let open = false; function toggleOpen() { open = !open; }");
    const overrides = list<ImportOverride>();
    const result = emit(&component, &overrides) catch (code) {
        assert(code == JavaScriptError.unsupported_template);
        return;
    };
    assert(mem.contains(result.code.bytes(), "updateRegion_conditional_".bytes()));
}
test "flat module preserves render mutation error rather than backend failure" {
    const component = browser("{{value++}}", "");
    const overrides = list<ImportOverride>();
    const result = emit(&component, &overrides) catch (code) {
        assert(code == JavaScriptError.unsupported_render_expression);
        return;
    };
    assert(false);
}
test "bound class boolean value style aria and general attributes select separate operations" {
    const output = compiled_module("<input class=\"base\" bind:class=\"props.title\" bind:checked=\"value\" bind:value=\"value\" bind:style=\"props.title\" bind:aria-label=\"false\" bind:data-x=\"value\"/>");
    assert(mem.contains(output.code.bytes(), "filter(Boolean).join(\" \")".bytes()));
    assert(mem.contains(output.code.bytes(), "Boolean(__value_0_checked)".bytes()));
    assert(mem.contains(output.code.bytes(), "__next_string_0_value".bytes()));
    assert(mem.contains(output.code.bytes(), "style.cssText = __value_0_style".bytes()));
    assert(mem.contains(output.code.bytes(), "String(__value_0_aria_label)".bytes()));
}

test "explicit empty cell selection rejects template writes to untracked script locals" {
    const component = browser("<button @click=\"value++\">{{value}}</button>", "");
    const overrides = list<ImportOverride>();
    const result = emit(&component, &overrides) catch (code) {
        assert(code == JavaScriptError.cell_template_untracked_assignment_unsupported);
        return;
    };
    assert(false);
}

test "explicit local cell selection lowers template writes and subscribes to dirty bindings" {
    const component = browser("<button @click=\"value++\">{{value}}</button>", "");
    const overrides = list<ImportOverride>();
    var names = list<string>();
    names.push("value");
    var subscriptions = list<LocalSubscription>();
    subscriptions.push({
        name: "value",
        binding: "value",
        publisher_backed: false
    });
    const selection: CellSelection = {
        local_names: names,
        local_subscriptions: subscriptions,
        managed_subscriptions: list<ManagedSubscription>()
    };
    const output = emit_with_selection(&component, &overrides, &selection) catch (code) {
        panic("Expected selected cell module");
    };
    assert(mem.contains(output.code.bytes(), "__weiv_scope.value = value.value;".bytes()));
    assert(mem.contains(output.code.bytes(), "__weiv_cellScope.watch(value, \"value\");".bytes()));
}

test "managed publisher selection emits module import and watcher" {
    const component = browser("<p>{{value}}</p>", "");
    const overrides = list<ImportOverride>();
    var publishers = list<ManagedSubscription>();
    publishers.push({
        specifier: "./state.mjs",
        name: "counter",
        binding: "value"
    });
    const selection: CellSelection = {
        local_names: list<string>(),
        local_subscriptions: list<LocalSubscription>(),
        managed_subscriptions: publishers
    };
    const output = emit_with_selection(&component, &overrides, &selection) catch (code) {
        panic("Expected publisher module");
    };
    assert(mem.contains(output.code.bytes(), "import { moduleState as __weiv_publisher_0 } from \"./state.mjs\";".bytes()));
    assert(mem.contains(output.code.bytes(), "__weiv_cellScope.watch(__weiv_publisher_0.getCell(\"counter\"), \"value\");".bytes()));
}

test "selected observable import watches its requested binding" {
    const component = browser("<p>{{state}}</p>", "import {state} from './state.ts';");
    const overrides = list<ImportOverride>();
    var subscriptions = list<LocalSubscription>();
    subscriptions.push({
        name: "state",
        binding: "state",
        publisher_backed: false
    });
    const selection: CellSelection = {
        local_names: list<string>(),
        local_subscriptions: subscriptions,
        managed_subscriptions: list<ManagedSubscription>()
    };
    const output = emit_with_selection(&component, &overrides, &selection) catch (code) {
        panic("Expected observable import module");
    };
    assert(mem.contains(output.code.bytes(), "if (__weiv_isObservable(__weiv_import_state))".bytes()));
    assert(mem.contains(output.code.bytes(), "__weiv_cellScope.watch(__weiv_importedCell, \"state\");".bytes()));
}

test "region dependencies automatically subscribe observable imports" {
    const component = browser("<p>{{state}}</p>", "import {state} from './state.ts';");
    var selection = empty();
    select_into(&component, &selection);
    assert(selection.local_subscriptions.len() == 1);
    assert(selection.local_subscriptions[0].name == "state");
}

test "region dependencies select local cells for template event assignments" {
    const component = browser("<button @click=\"value++\">{{value}}</button>", "");
    const overrides = list<ImportOverride>();
    const output = emit_with_local_state(&component, &overrides) catch (code) {
        panic("Expected inferred local cell module");
    };
    assert(mem.contains(output.code.bytes(), "__weiv_scope.value = value.value;".bytes()));
    assert(mem.contains(output.code.bytes(), "__weiv_cellScope.watch(value, \"value\");".bytes()));
}

test "evaluator planning uses explicit scope tasks for deeply nested loops" {
    var text = list<u8>();
    var i: usize = 0;
    while i<256 {
        for byte in "<p #for=\"item in items\">".bytes() {
            text.push(byte);
        }
        i = i + 1;
    }
    for byte in "{{item}}".bytes() {
        text.push(byte);
    }
    i = 0;
    while i<256 {
        for byte in "</p>".bytes() {
            text.push(byte);
        }
        i = i + 1;
    }
    const output = plan(string.from(text.view()), "");
    assert(output.records.len() == 257);
    assert(output.records[256].site == EvaluatorSite.interpolation);
}
test "module emission rejects a mismatched region graph instead of routing the wrong update" {
    var component = browser("{{value}}", "");
    const region = component.region_graph.regions.get_mut(0);
    region.ref_id = 99;
    const overrides = list<ImportOverride>();
    const result = emit(&component, &overrides) catch (code) {
        assert(code == JavaScriptError.region_graph_mismatch);
        return;
    };
    assert(false);
}
