import { parse } from .compiler.parser.template.parse;
import { normalize } from .compiler.parser.template.normalize;
import { bind } from .compiler.sema.bind_template;
import { ScriptFacts, ScriptBinding, StateFacts, HelperFacts, MutationFacts, AliasFacts, CallbackRegistrationFacts, ScriptImport, ScriptDiagnostic } from .compiler.sema.script_facts;
import { TemplateBindings, BindingSource } from .compiler.sema.template_bindings;
import { ComponentManifests, ComponentSlotManifest } from .compiler.sema.component_manifests;
import { SlotManifest, SlotEntry } from .compiler.sema.slot_manifest;

fn script_with(names: []const string): ScriptFacts {
    var bindings = list<ScriptBinding>();
    for name in names {
        bindings.push(ScriptBinding {
            name: name,
            kind: "immutable",
            exported: false,
            template_visible: true,
            callable: false,
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
        imports: list<ScriptImport>(),
        bindings: bindings,
        state_facts: {
            helpers: list<HelperFacts>(),
            mutations: list<MutationFacts>(),
            aliases: list<AliasFacts>(),
            callback_registrations: list<CallbackRegistrationFacts>()
        },
        diagnostics: list<ScriptDiagnostic>()
    };
}

fn bind_with(source: string, script: &const ScriptFacts, catalogs: &const ComponentManifests): TemplateBindings {
    const raw = parse(source.bytes()) catch (code) {
        panic("Expected parse");
    };
    const normalized = normalize(&raw) catch (code) {
        panic("Expected normalization");
    };
    return bind(source.bytes(), &raw, &normalized, script, catalogs);
}

fn basic(source: string, names: []const string): TemplateBindings {
    const script = script_with(names);
    const catalogs: ComponentManifests = {
        entries: list<ComponentSlotManifest>()
    };
    return bind_with(source, &script, &catalogs);
}

fn count_kind(result: &const TemplateBindings, kind: string): usize {
    var count: usize = 0;
    var i: usize = 0;
    while i < result.diagnostics.len() {
        const diagnostic = &result.diagnostics[i];
        if diagnostic.kind == kind {
            count = count + 1;
        }
        i = i + 1;
    }
    return count;
}

fn named_catalog(): ComponentManifests {
    var slots = list<SlotEntry>();
    slots.push(SlotEntry {
        name: "head",
        span: {
            start: 0,
            end: 0
        }
    });
    var entries = list<ComponentSlotManifest>();
    entries.push(ComponentSlotManifest {
        tag_name: "Card",
        manifest: SlotManifest {
            entries: slots
        }
    });
    return {
        entries: entries
    };
}

fn helper_script(external: bool, side_effects: bool): ScriptFacts {
    const names: [1]string = ["helper"];
    var script = script_with(names[..1]);
    script.bindings[0] = ScriptBinding {
        name: "helper",
        kind: "function",
        exported: false,
        template_visible: true,
        callable: true,
        type_annotation: none,
        span: {
            start: 0,
            end: 6
        }
    };
    script.state_facts.helpers.push(HelperFacts {
        name: "helper",
        kind: "function",
        span: {
            start: 0,
            end: 6
        },
        reads: list<string>(),
        writes: list<string>(),
        calls: list<string>(),
        async_flag: false,
        returns_expression_only: false,
        contains_external_reads: external,
        contains_side_effects: side_effects
    });
    return script;
}

test "visible references retain encounter order and later calls upgrade flags" {
    const names: [2]string = ["first", "second"];
    const result = basic("{{ first + second + first() }}", names[..2]);
    assert(result.expressions.len() == 1);
    assert(result.expressions[0].references.len() == 2);
    assert(result.expressions[0].references[0].name == "first");
    assert(result.expressions[0].references[0].call);
    assert(result.expressions[0].references[1].name == "second");
    assert(not result.expressions[0].references[1].call);
    assert(result.diagnostics.len() == 0);
}

test "unknown identifiers are diagnosed once per expression using legacy offsets" {
    const names: [0]string = [];
    const result = basic("{{ missing + missing() }}", names[..0]);
    assert(result.expressions[0].references.len() == 0);
    assert(result.diagnostics.len() == 1);
    assert(result.diagnostics[0].kind == "unresolved_binding");
    assert(result.diagnostics[0].severity == "error");
    assert(result.diagnostics[0].name == "missing");
    assert(result.diagnostics[0].origin == BindingSource.template);
    assert(result.diagnostics[0].span.start == 0);
    assert(result.diagnostics[0].span.end == 7);
    assert(result.expressions[0].source.start == 3);
}

test "properties quotes keywords spread and template strings follow lexical contract" {
    const names: [2]string = ["user", "spread"];
    const result = basic("{{ user.name + ...spread + 'ignored' + `hello ${user.name}` + true + typeof user + emit('x') }}", names[..2]);
    assert(result.diagnostics.len() == 0);
    assert(result.expressions[0].references.len() == 3);
    assert(result.expressions[0].references[0].name == "user");
    assert(result.expressions[0].references[1].name == "spread");
    assert(result.expressions[0].references[2].name == "emit");
}

test "loop iterable binds before aliases and aliases expire at subtree end" {
    const names: [1]string = ["items"];
    const result = basic("<p #for=\"item in items\">{{item}}</p>{{item}}", names[..1]);
    assert(result.expressions.len() == 3);
    assert(result.expressions[0].references[0].name == "items");
    assert(result.expressions[1].references[0].name == "item");
    assert(result.expressions[2].references.len() == 0);
    assert(count_kind(&result, "unresolved_binding") == 1);
    const own = basic("<p #for=\"item in item\">{{item}}</p>", names[..1]);
    assert(count_kind(&own, "unresolved_binding") == 1);
}

test "nested loop shadowing and conditional branches retain lexical visibility" {
    const names: [2]string = ["items", "other"];
    const result = basic("<a #for=\"item in items\"><b #for=\"item in other\">{{item}}</b><c #if=\"item\">{{item}}</c><d #else>{{item}}</d></a>", names[..2]);
    assert(result.diagnostics.len() == 0);
    assert(result.expressions.len() == 6);
}

test "uppercase component resolution is lexical and catalog absence is allowed" {
    const names: [1]string = ["Card"];
    const result = basic("<Card/><Missing/><custom-element/>", names[..1]);
    assert(result.component_refs.len() == 2);
    assert(result.component_refs[0].resolved);
    assert(not result.component_refs[1].resolved);
    assert(count_kind(&result, "unresolved_component") == 1);
}

test "hidden bindings do not resolve names or component tags" {
    const names: [1]string = ["Hidden"];
    var script = script_with(names[..1]);
    script.bindings[0] = ScriptBinding {
        name: "Hidden",
        kind: "type",
        exported: false,
        template_visible: false,
        callable: false,
        type_annotation: none,
        span: {
            start: 0,
            end: 0
        }
    };
    const catalogs: ComponentManifests = {
        entries: list<ComponentSlotManifest>()
    };
    const result = bind_with("<Hidden>{{Hidden}}</Hidden>", &script, &catalogs);
    assert(count_kind(&result, "unresolved_component") == 1);
    assert(count_kind(&result, "unresolved_binding") == 1);
}

test "own duplicate outlets precede reserved framework diagnostics" {
    const names: [1]string = ["emit"];
    const result = basic("<slot/><slot/>", names[..1]);
    assert(result.own_slot_manifest.entries.len() == 2);
    assert(result.diagnostics.len() == 2);
    assert(result.diagnostics[0].kind == "slot.duplicate_outlet");
    assert(result.diagnostics[0].name == "default");
    assert(result.diagnostics[1].kind == "framework.reserved_binding");
    assert(result.diagnostics[1].origin == BindingSource.script);
    assert(result.diagnostics[0].origin == BindingSource.template);
    const allowed = basic("{{emit('x')}}", names[..0]);
    assert(allowed.diagnostics.len() == 0);
}

test "legacy directive warnings precede expression errors and Vue warnings" {
    const names: [0]string = [];
    const result = basic("<p v-if=\"x\" v-for=\"x\" on:click=\"missing\" bind:value=\"other\"/>", names[..0]);
    assert(result.diagnostics.len() == 6);
    assert(result.diagnostics[0].kind == "directive.vue_structural_syntax");
    assert(result.diagnostics[1].kind == "directive.vue_structural_syntax");
    assert(result.diagnostics[2].kind == "directive.deprecated_syntax");
    assert(result.diagnostics[3].kind == "unresolved_binding");
    assert(result.diagnostics[4].kind == "directive.deprecated_syntax");
    assert(result.diagnostics[5].kind == "unresolved_binding");
    assert(result.diagnostics[2].severity == "warning");
}

test "helper warning priority and first-occurrence dedup match Zig" {
    const script = helper_script(true, true);
    const catalogs: ComponentManifests = {
        entries: list<ComponentSlotManifest>()
    };
    const result = bind_with("{{helper() + helper()}}", &script, &catalogs);
    assert(count_kind(&result, "helper.external_state") == 1);
    assert(count_kind(&result, "helper.side_effects") == 0);
    const later = bind_with("{{helper + helper()}}", &script, &catalogs);
    assert(later.diagnostics.len() == 0);
    assert(later.expressions[0].references[0].call);
    const effects = helper_script(false, true);
    const effect_result = bind_with("{{helper()}}", &effects, &catalogs);
    assert(count_kind(&effect_result, "helper.side_effects") == 1);
}

test "provided manifests validate named and unnamed content independently" {
    const names: [1]string = ["Card"];
    const script = script_with(names[..1]);
    const catalog = named_catalog();
    const result = bind_with("<Card><p slot:unknown/>text</Card>", &script, &catalog);
    assert(result.component_refs[0].resolved);
    assert(result.diagnostics.len() == 2);
    assert(result.diagnostics[0].kind == "slot.unknown_name");
    assert(result.diagnostics[1].kind == "slot.default_not_supported");
    const known = bind_with("<Card><p slot:head/></Card>", &script, &catalog);
    assert(known.diagnostics.len() == 0);
}

test "duplicate provision tracking preserves last grouping kind" {
    const names: [1]string = ["Card"];
    const grouped = basic("<Card><template slot:head/><template slot:head/></Card>", names[..1]);
    assert(grouped.diagnostics.len() == 0);
    const mixed = basic("<Card><template slot:head/><p slot:head/><template slot:head/></Card>", names[..1]);
    assert(count_kind(&mixed, "slot.duplicate_provision") == 2);
}

test "structural child wrappers are unnamed content rather than direct provisions" {
    const names: [2]string = ["Card", "ok"];
    const script = script_with(names[..2]);
    const catalog = named_catalog();
    const result = bind_with("<Card><p #if=\"ok\" slot:unknown/></Card>", &script, &catalog);
    assert(count_kind(&result, "slot.unknown_name") == 0);
    assert(count_kind(&result, "slot.default_not_supported") == 1);
}

test "slot fallback expressions bind even though nested outlets are not exported" {
    const names: [0]string = [];
    const result = basic("<slot><slot name=\"hidden\"/>{{missing}}</slot>", names[..0]);
    assert(result.own_slot_manifest.entries.len() == 1);
    assert(result.expressions.len() == 1);
    assert(count_kind(&result, "unresolved_binding") == 1);
}

test "binding reads inputs without mutation and can repeat" {
    const source = "{{value}}";
    const names: [1]string = ["value"];
    const script = script_with(names[..1]);
    const raw = parse(source.bytes()) catch (code) {
        panic("Expected parse");
    };
    const normalized = normalize(&raw) catch (code) {
        panic("Expected normalization");
    };
    const catalogs: ComponentManifests = {
        entries: list<ComponentSlotManifest>()
    };
    const first = bind(source.bytes(), &raw, &normalized, &script, &catalogs);
    const second = bind(source.bytes(), &raw, &normalized, &script, &catalogs);
    assert(first.expressions[0].references[0].name == second.expressions[0].references[0].name);
    assert(raw.nodes.len() == 1);
    assert(normalized.nodes.len() == 1);
    assert(script.bindings.len() == 1);
}

test "deep lexical loop scopes are iterative and expire after the enclosing subtree" {
    var bytes = list<u8>();
    var depth: usize = 0;
    while depth < 256 {
        for byte in "<p #for=\"item in items\">".bytes() {
            bytes.push(byte);
        }
        depth = depth + 1;
    }
    for byte in "{{item}}".bytes() {
        bytes.push(byte);
    }
    depth = 0;
    while depth < 256 {
        for byte in "</p>".bytes() {
            bytes.push(byte);
        }
        depth = depth + 1;
    }
    for byte in "{{item}}".bytes() {
        bytes.push(byte);
    }
    const source = string.from(bytes.view());
    const names: [1]string = ["items"];
    const result = basic(source, names[..1]);
    assert(result.expressions.len() == 258);
    assert(result.expressions[256].references[0].name == "item");
    assert(result.expressions[257].references.len() == 0);
    assert(count_kind(&result, "unresolved_binding") == 1);
}
