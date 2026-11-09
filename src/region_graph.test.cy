import { ScriptFacts, ScriptBinding, ScriptImport, ScriptDiagnostic, HelperFacts, MutationFacts, AliasFacts, CallbackRegistrationFacts } from .compiler.sema.script_facts;
import { parse } from .compiler.parser.template.parse;
import { normalize } from .compiler.parser.template.normalize;
import { bind } from .compiler.sema.bind_template;
import { ComponentManifests, ComponentSlotManifest } from .compiler.sema.component_manifests;
import { lower as lower_lir } from .compiler.lower.lower_template;
import { lower as render } from .compiler.backend.browser.render_tree.lower;
import { build } from .compiler.backend.browser.build_region_graph;
import { RegionGraph, RegionKind, region_kind_label } from .compiler.backend.browser.region_graph;

fn facts(): ScriptFacts {
    var bindings = list<ScriptBinding>();
    const names: [7]string = ["a", "b", "items", "imported", "state", "Card", "helper"];
    for name in names {
        bindings.push(ScriptBinding {
            name: name,
            kind: "immutable",
            exported: false,
            template_visible: true,
            callable: name == "helper",
            type_annotation: none,
            span: {
                start: 0,
                end: 0
            }
        });
    }
    var imports = list<ScriptImport>();
    imports.push(ScriptImport {
        source: "./store",
        kind: "named",
        imported_name: "imported",
        local_name: "imported",
        span: {
            start: 0,
            end: 0
        }
    });
    var reads = list<string>();
    reads.push("state");
    reads.push("a");
    var calls = list<string>();
    calls.push("imported");
    var helpers = list<HelperFacts>();
    helpers.push(HelperFacts {
        name: "helper",
        kind: "function",
        span: {
            start: 0,
            end: 0
        },
        reads: reads,
        calls: calls,
        writes: list<string>(),
        async_flag: false,
        returns_expression_only: true,
        contains_external_reads: false,
        contains_side_effects: false
    });
    return {
        ok: true,
        source_path: "test.ts",
        props: none,
        bindings: bindings,
        imports: imports,
        diagnostics: list<ScriptDiagnostic>(),
        state_facts: {
            helpers: helpers,
            mutations: list<MutationFacts>(),
            aliases: list<AliasFacts>(),
            callback_registrations: list<CallbackRegistrationFacts>()
        }
    };
}
fn plan(source: string): RegionGraph {
    const script = facts();
    const raw = parse(source.bytes()) catch (code) {
        panic("Expected template");
    };
    const normalized = normalize(&raw) catch (code) {
        panic("Expected normalization");
    };
    const catalogs: ComponentManifests = {
        entries: list<ComponentSlotManifest>()
    };
    const bindings = bind(source.bytes(), &raw, &normalized, &script, &catalogs);
    const lir = lower_lir(source.bytes(), &raw, &normalized, &bindings) catch (code) {
        panic("Expected LIR");
    };
    const tree = render(&lir);
    return build(source.bytes(), &script, &lir, &tree);
}
fn names(graph: &const RegionGraph, index: usize, expected: string): void {
    const region = &graph.regions[index];
    var bytes = list<u8>();
    var i: usize = 0;
    while i < region.dependency_names.len() {
        if i > 0 {
            bytes.push(44);
        }
        for byte in region.dependency_names[i].bytes() {
            bytes.push(byte);
        }
        i = i + 1;
    }
    assert(string.from(bytes.view()) == expected);
}
fn no_hint(source: string): void {
    const graph = plan(source);
    assert(graph.regions.len() == 1);
    if graph.regions[0].precise_import_name is name {
        assert(false);
    }
}

test "static templates and HTML event-only nodes create no regions" {
    const empty = plan("");
    const static = plan("<p title=\"static\">literal</p><button @click=\"imported.value\"/>");
    assert(empty.regions.len() == 0);
    assert(static.regions.len() == 0);
    assert(static.table.roots.len() == 0);
    assert(static.table.paths.len() == 0);
}

test "ordinary element binds precede child text regions despite postorder refs" {
    const graph = plan("<div bind:title=\"a\" :class=\"b\">{{imported.value}}</div>{{a}}");
    assert(graph.regions.len() == 4);
    assert(graph.regions[0].id == 1);
    assert(graph.regions[0].kind == RegionKind.attribute);
    assert(graph.regions[0].ref_id == 1);
    assert(graph.regions[1].ref_id == 1);
    assert(graph.regions[2].ref_id == 0);
    assert(graph.regions[3].ref_id == 2);
    assert(graph.regions[2].kind == RegionKind.text);
    names(&graph, 0, "a");
    names(&graph, 1, "b");
    names(&graph, 2, "imported");
    if graph.regions[0].name is name {
        assert(name == "title");
    } else {
        assert(false);
    }
    if graph.regions[1].name is name {
        assert(name == "class");
    } else {
        assert(false);
    }
    assert(graph.regions[0].node_id == 0);
    assert(graph.regions[2].node_id == 1);
    assert(graph.regions[0].span.start == 0);
}

test "region IDs have a checked conversion distinct from render references" {
    const graph = plan("{{a}}{{b}}");
    if graph.region_index(1) is index {
        assert(index == 0);
    } else {
        assert(false);
    }
    if graph.region_index(2) is index {
        assert(index == 1);
    } else {
        assert(false);
    }
    if graph.region_index(0) is index {
        assert(false);
    }
    if graph.region_index(3) is index {
        assert(false);
    }
    assert(graph.regions[0].ref_id == 0);
}

test "simple imported paths receive a precise hint and reuse canonical path IDs" {
    const graph = plan("{{ imported.user.name }}<p bind:title=\"imported.user.name\"/>");
    assert(graph.regions.len() == 2);
    assert(graph.table.paths.len() == 3);
    assert(graph.regions[0].tracked_path_ids[0] == 3);
    assert(graph.regions[1].tracked_path_ids[0] == 3);
    if graph.regions[0].precise_import_name is name {
        assert(name == "imported");
    } else {
        assert(false);
    }
    if graph.regions[1].precise_import_name is name {
        assert(name == "imported");
    } else {
        assert(false);
    }
}

test "precise hints reject arithmetic multiple paths internal whitespace calls and local roots" {
    no_hint("{{imported.value + 1}}");
    no_hint("{{imported.a + imported.b}}");
    no_hint("{{ imported . value }}");
    no_hint("{{imported}}");
    no_hint("{{imported.value()}}");
    no_hint("{{state.user.name}}");
}

test "conditional owns all branch descendants but tracks only its header expression" {
    const graph = plan("<p #if=\"imported.ready\">{{state.deep}}<i bind:title=\"a\"/></p><b #else>{{b}}</b>");
    assert(graph.regions.len() == 1);
    assert(graph.regions[0].kind == RegionKind.conditional);
    assert(graph.regions[0].ref_id == 2);
    names(&graph, 0, "imported,state,a,b");
    assert(graph.regions[0].tracked_path_ids.len() == 1);
    assert(graph.table.paths.len() == 2);
    assert(graph.table.paths[1].path == "imported.ready");
    if graph.regions[0].precise_import_name is name {
        assert(false);
    }
}

test "loop owns descendants filters aliases and records the iterable path and alias name" {
    const graph = plan("<i #for=\"item in items.list\">{{item.name}}<b>{{a}}</b></i>");
    assert(graph.regions.len() == 1);
    assert(graph.regions[0].kind == RegionKind.loop);
    assert(graph.regions[0].ref_id == 2);
    names(&graph, 0, "items,a");
    if graph.regions[0].name is name {
        assert(name == "item");
    } else {
        assert(false);
    }
    assert(graph.table.paths[1].path == "items.list");
}

test "component owns projected dependency closure while collecting only direct effect paths" {
    const graph = plan("<Card bind:title=\"imported.title\" @pick=\"state.handler\"><p slot:head>{{state.deep}}</p>{{a}}</Card>");
    assert(graph.regions.len() == 1);
    assert(graph.regions[0].kind == RegionKind.child);
    assert(graph.regions[0].ref_id == 5);
    names(&graph, 0, "imported,state,a");
    if graph.regions[0].name is name {
        assert(name == "Card");
    } else {
        assert(false);
    }
    assert(graph.regions[0].tracked_path_ids.len() == 2);
    if graph.table.find_path("state.deep") is id {
        assert(false);
    }
    if graph.table.find_path("state.handler") is id {} else {
        assert(false);
    }
}

test "slot outlet owns fallback dependencies without collecting descendant paths" {
    const graph = plan("<slot name=\"head\"><p bind:title=\"imported.deep\">{{a}}</p></slot>");
    assert(graph.regions.len() == 1);
    assert(graph.regions[0].kind == RegionKind.slot);
    assert(graph.regions[0].ref_id == 2);
    names(&graph, 0, "imported,a");
    assert(graph.regions[0].tracked_path_ids.len() == 0);
    assert(graph.table.paths.len() == 0);
    if graph.regions[0].name is name {
        assert(name == "head");
    } else {
        assert(false);
    }
}

test "empty and named slots remain regions with stable handle references" {
    const graph = plan("<slot/><slot name=\"x\"/>");
    assert(graph.regions.len() == 2);
    assert(graph.regions[0].ref_id == 2);
    assert(graph.regions[1].ref_id == 5);
    if graph.regions[0].name is name {
        assert(false);
    }
    if graph.regions[1].name is name {
        assert(name == "x");
    } else {
        assert(false);
    }
}

test "constant expressions retain regions even without dependency names or paths" {
    const graph = plan("{{42}}<p bind:title=\"true\"/>");
    assert(graph.regions.len() == 2);
    names(&graph, 0, "");
    names(&graph, 1, "");
    assert(graph.table.paths.len() == 0);
}

test "region planning retains imported calls and helper dependency closure" {
    const graph = plan("{{helper()}}<Card @pick=\"imported()\"/>");
    assert(graph.regions.len() == 2);
    names(&graph, 0, "helper,state,a,imported");
    names(&graph, 1, "imported");
    assert(graph.regions[0].tracked_path_ids.len() == 0);
}

test "finished graph owns all strings and collections after inputs are destroyed" {
    const graph = plan("<p bind:title=\"imported.user\">{{a}}</p><slot name=\"owned\"/>");
    assert(graph.regions.len() == 3);
    assert(graph.table.roots[0].binding_name == "imported");
    assert(graph.table.paths[1].path == "imported.user");
    names(&graph, 0, "imported");
    if graph.regions[0].precise_import_name is name {
        assert(name == "imported");
    } else {
        assert(false);
    }
    if graph.regions[2].name is name {
        assert(name == "owned");
    } else {
        assert(false);
    }
}

test "graph builds repeat independently with stable region and path IDs" {
    const first = plan("{{state.x}}{{imported.x}}");
    const second = plan("{{state.x}}{{imported.x}}");
    assert(first.regions.len() == second.regions.len());
    assert(first.table.paths.len() == second.table.paths.len());
    assert(first.regions[1].id == 2);
    assert(second.regions[1].tracked_path_ids[0] == 4);
    assert(region_kind_label(RegionKind.child) == "child");
}

test "deep ordinary trees allocate one text region with original provenance" {
    var bytes = list<u8>();
    var i: usize = 0;
    while i < 512 {
        for byte in "<a>".bytes() {
            bytes.push(byte);
        }
        i = i + 1;
    }
    for byte in "{{imported.value}}".bytes() {
        bytes.push(byte);
    }
    i = 0;
    while i < 512 {
        for byte in "</a>".bytes() {
            bytes.push(byte);
        }
        i = i + 1;
    }
    const graph = plan(string.from(bytes.view()));
    assert(graph.regions.len() == 1);
    assert(graph.regions[0].node_id == 512);
    assert(graph.regions[0].span.start == 1536);
    assert(graph.regions[0].ref_id == 0);
}

test "nested structural nodes form one owning region with complete dependency closure" {
    var bytes = list<u8>();
    var i: usize = 0;
    while i < 256 {
        for byte in "<i #if=\"a\">".bytes() {
            bytes.push(byte);
        }
        i = i + 1;
    }
    for byte in "{{imported.value}}".bytes() {
        bytes.push(byte);
    }
    i = 0;
    while i < 256 {
        for byte in "</i>".bytes() {
            bytes.push(byte);
        }
        i = i + 1;
    }
    const graph = plan(string.from(bytes.view()));
    assert(graph.regions.len() == 1);
    names(&graph, 0, "a,imported");
    assert(graph.table.paths.len() == 0);
}
