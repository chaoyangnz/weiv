import { decode as mutation_result, MutationProbeError } from .compiler.sema.decode_mutation_probe;
import { parse } from .compiler.parser.template.parse;
import { normalize } from .compiler.parser.template.normalize;
import { compile_report, take_unit } from .compiler.compile;
import { TemplateFunctionInputs, TemplateFunctionInput, TemplateFunctions } from .compiler.lower.template_functions;
import { collect } from .compiler.lower.collect_template_functions;
import { build, append, TemplateFunctionError } from .compiler.lower.build_template_functions;
import { ComponentManifests, ComponentSlotManifest } from .compiler.sema.component_manifests;
import { text } from .compiler.sema.binding_context;
import { analyze_module_state_raw, handler_supported, handler_kind, ScriptBackendError } from .ffi.script_backend;

fn inputs(template: string, script: string): TemplateFunctionInputs {
    const source = $"<template>{template}</template><script lang=\"ts\">{script}</script>";
    const manifests: ComponentManifests = {
        entries: list<ComponentSlotManifest>()
    };
    var report = compile_report(source, "functions.weiv", &manifests);
    const unit = take_unit(&report) catch (code) {
        panic("Expected unit");
    };
    const bytes = unit.source.bytes();
    const fragment = bytes[unit.sfc_document.template.content_span.start..unit.sfc_document.template.content_span.end];
    return collect(fragment, &unit.template_document, &unit.normalized_template, &unit.script.facts);
}
fn basic_inputs(template: string): TemplateFunctionInputs {
    return inputs(template, "export interface Props {} export let props: Props;");
}
fn built(template: string, pure: bool): TemplateFunctions {
    const records = basic_inputs(template);
    return build(template.bytes(), &records, pure, "[") catch (code) {
        panic("Expected functions");
    };
}
fn primitive(source: string, locals: &const List<string>, names: &const List<string>, argument: ?string): string {
    var output = list<u8>();
    const range = append(&output, source, locals, names, argument) catch (code) {
        panic("Expected wrapper");
    };
    assert(text(output.view(), range) == source);
    return string.from(output.view());
}

test "lexical input snapshot owns names and preserves binding import order and duplicates" {
    const result = inputs("{{x}}", "import { x as other } from './m'; import './side'; export interface Props {} export let props: Props; const hidden = 1; export const x = 2;");
    assert(result.expressions.len() == 1);
    // Script binding order precedes import order, exactly as the backend supplies it.
    assert(result.script_names.len() >= 2);
    assert(result.script_names[result.script_names.len() - 1] == "other");
}

test "preorder expressions capture loop scope after iterable and expire at subtree end" {
    const source = "<i #for=\"item in items\">{{item}}<b #for=\"item in item.children\" @click=\"item.run\"/></i>{{outside}}";
    const result = basic_inputs(source);
    assert(result.expressions.len() == 5);
    assert(text(source.bytes(), result.expressions[0].expression) == "items");
    assert(result.expressions[0].locals.len() == 0);
    assert(result.expressions[1].locals.len() == 1);
    assert(result.expressions[2].locals.len() == 1);
    assert(text(source.bytes(), result.expressions[2].expression) == "item.children");
    assert(result.expressions[3].locals.len() == 2);
    assert(result.expressions[3].locals[0] == "item");
    assert(result.expressions[3].locals[1] == "item");
    assert(result.expressions[4].locals.len() == 0);
}

test "component and HTML event arguments include projected groups and slot fallback" {
    const source = "<Card @pick=\"onPick\"><template slot:head @click=\"group\"><p bind:title=\"title\" @click=\"onClick\"/></template></Card><slot>{{fallback}}</slot>";
    const result = basic_inputs(source);
    assert(result.expressions.len() == 5);
    if result.expressions[0].argument is name {
        assert(name == "payload");
    } else {
        assert(false);
    }
    if result.expressions[1].argument is name {
        assert(name == "event");
    } else {
        assert(false);
    }
    if result.expressions[2].argument is name {
        assert(false);
    }
    if result.expressions[3].argument is name {
        assert(name == "event");
    } else {
        assert(false);
    }
    assert(text(source.bytes(), result.expressions[4].expression) == "fallback");
}

test "conditional alternate ordering preserves each branch scope" {
    const source = "<p #if=\"ok\"><i #for=\"item in items\">{{item}}</i></p><p #else>{{other}}</p>";
    const result = basic_inputs(source);
    assert(result.expressions.len() == 4);
    assert(text(source.bytes(), result.expressions[0].expression) == "ok");
    assert(text(source.bytes(), result.expressions[1].expression) == "items");
    assert(result.expressions[2].locals.len() == 1);
    assert(result.expressions[3].locals.len() == 0);
}

test "wrappers preserve render direct handler and runtime conditional handler forms" {
    const empty = list<string>();
    assert(primitive("value", &empty, &empty, none) == "(__weiv_context)=>{\nreturn (value);\n}");
    assert(primitive("save", &empty, &empty, "event") == "(__weiv_context,__weiv_argument)=>{\nconst event=__weiv_argument;\nreturn (save)?.(__weiv_argument);\n}");
    assert(primitive("count++", &empty, &empty, "event") == "(__weiv_context,__weiv_argument)=>{\nconst event=__weiv_argument;\nreturn (count++);\n}");
    assert(primitive("ok ? save : false", &empty, &empty, "payload") == "(__weiv_context,__weiv_argument)=>{\nconst payload=__weiv_argument;\nreturn ((__weiv_handler)=>typeof __weiv_handler===\"function\"?__weiv_handler(__weiv_argument):__weiv_handler)((ok ? save : false));\n}");
}

test "inner aliases shadow earlier locals and loop alias shadows handler argument" {
    var locals = list<string>();
    locals.push("item");
    locals.push("event");
    locals.push("item");
    const empty = list<string>();
    assert(primitive("item", &locals, &empty, "event") == "(__weiv_context,__weiv_argument)=>{\nconst event=__weiv_context[\"event\"];\nconst item=__weiv_context[\"item\"];\nreturn (item)?.(__weiv_argument);\n}");
    var names = list<string>();
    names.push("event");
    assert(primitive("event", &empty, &names, "event") == "(__weiv_context,__weiv_argument)=>{\nreturn (event)?.(__weiv_argument);\n}");
}

test "reserved aliases fail even when a later alias would shadow them" {
    var locals = list<string>();
    locals.push("__weiv_bad");
    locals.push("__weiv_bad");
    const empty = list<string>();
    var output = list<u8>();
    const result = append(&output, "value", &locals, &empty, none) catch (code) {
        assert(code == TemplateFunctionError.reserved_identifier);
        return;
    };
    assert(false);
}

test "collection filters pure render expressions but keeps mutations and event handlers" {
    const source = "{{value}}<p bind:title=\"count++\" @click=\"save\"/>";
    const mutations = built(source, false);
    const all = built(source, true);
    assert(mutations.records.len() == 2);
    assert(all.records.len() == 3);
    assert(text(source.bytes(), mutations.records[0].template) == "count++");
    assert(text(source.bytes(), mutations.records[1].template) == "save");
}

test "unsupported expressions are skipped while valid siblings retain order" {
    const source = "{{await foo()}}{{value}}";
    const result = built(source, true);
    assert(result.records.len() == 1);
    assert(text(source.bytes(), result.records[0].template) == "value");
}

test "generated ranges include prefix and point exactly at original expression bytes" {
    const source = "<a #if=\"a\">{{a}}</a>{{a}}";
    const result = built(source, true);
    assert(result.records.len() == 3);
    assert(result.records[0].template.start == 8);
    assert(result.records[1].template.start == 13);
    assert(result.records[2].template.start == 22);
    var i: usize = 0;
    while i < result.records.len() {
        const record = &result.records[i];
        assert(text(result.code.bytes(), record.generated) == text(source.bytes(), record.template));
        i = i + 1;
    }
}

test "empty expression collection preserves arbitrary prefix without separators" {
    const result = built("<p/>", true);
    assert(result.code == "[");
    assert(result.records.len() == 0);
}

test "backend probes return owned JSON and distinguish handler categories" {
    const raw = analyze_module_state_raw("const f = () => count++;", "template.ts") catch (code) {
        panic("Expected probe");
    };
    assert(raw.bytes().len() > 0);
    const direct = handler_kind("save") catch (code) {
        panic("Expected kind");
    };
    const dynamic = handler_kind("ok && save") catch (code) {
        panic("Expected kind");
    };
    const mutation = handler_kind("count++") catch (code) {
        panic("Expected kind");
    };
    assert(direct == 1);
    assert(dynamic == 2);
    assert(mutation == 0);
    const supported = handler_supported("save") catch (code) {
        panic("Expected support");
    };
    assert(supported);
}

test "malformed mutation probe responses fail explicitly" {
    const result = mutation_result("{\"ok\":true,\"bindings\":[{}]}") catch (code) {
        assert(code == MutationProbeError.invalid_response);
        return;
    };
    assert(false);
}

fn expect_probe_error(payload: string): void {
    const result = mutation_result(payload) catch (code) {
        assert(code == MutationProbeError.invalid_response);
        return;
    };
    assert(false);
}

test "mutation probe validates every record and preserves false or empty results" {
    const rejected = mutation_result("{\"ok\":false,\"bindings\":[{\"has_mutation\":true}]}") catch (code) {
        panic("Expected probe");
    };
    const empty = mutation_result("{\"ok\":true,\"bindings\":[]}") catch (code) {
        panic("Expected probe");
    };
    assert(not rejected);
    assert(not empty);
    expect_probe_error("{\"ok\":false}");
    expect_probe_error("{\"ok\":true,\"bindings\":[{\"has_mutation\":true},{}]}");
    expect_probe_error("{\"ok\":true,\"bindings\":[{\"has_mutation\":1}]}");
    expect_probe_error("null");
}

fn expect_nul(operation: i32): void {
    const bytes: [3]u8 = [97, 0, 98];
    const source = string.from(bytes[..3]);
    if operation == 0 {
        const result = handler_kind(source) catch (code) {
            assert(code == ScriptBackendError.embedded_nul);
            return;
        };
    } else if operation == 1 {
        const result = handler_supported(source) catch (code) {
            assert(code == ScriptBackendError.embedded_nul);
            return;
        };
    } else if operation == 2 {
        const result = analyze_module_state_raw(source, "template.ts") catch (code) {
            assert(code == ScriptBackendError.embedded_nul);
            return;
        };
    } else {
        const result = analyze_module_state_raw("const a=1;", source) catch (code) {
            assert(code == ScriptBackendError.embedded_nul);
            return;
        };
    }
    assert(false);
}

test "all new backend calls reject embedded NUL before foreign conversion" {
    expect_nul(0);
    expect_nul(1);
    expect_nul(2);
    expect_nul(3);
}

test "lexical scope capture is iterative for deeply nested templates" {
    var bytes = list<u8>();
    var i: usize = 0;
    while i < 256 {
        for byte in "<i #for=\"item in items\">".bytes() {
            bytes.push(byte);
        }
        i = i + 1;
    }
    for byte in "{{item}}".bytes() {
        bytes.push(byte);
    }
    i = 0;
    while i < 256 {
        for byte in "</i>".bytes() {
            bytes.push(byte);
        }
        i = i + 1;
    }
    for byte in "{{outside}}".bytes() {
        bytes.push(byte);
    }
    const source = string.from(bytes.view());
    const result = basic_inputs(source);
    assert(result.expressions.len() == 258);
    assert(result.expressions[0].locals.len() == 0);
    assert(result.expressions[255].locals.len() == 255);
    assert(result.expressions[256].locals.len() == 256);
    assert(result.expressions[257].locals.len() == 0);
}
