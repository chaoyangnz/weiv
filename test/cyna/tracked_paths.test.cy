import { Span } from .compiler.source;
import { ScriptFacts, ScriptBinding, ScriptImport, ScriptDiagnostic, PropsFacts, HelperFacts, MutationFacts, AliasFacts, CallbackRegistrationFacts } from .compiler.sema.script_facts;
import { LirDocument, LirNode, LirExpressionFacts, LirExpressionReference } from .compiler.lower.lir;
import { TrackedKind, kind_label, TrackedRoot } from .compiler.backend.browser.tracked_roots;
import { TrackedPaths, TrackedPath } from .compiler.backend.browser.tracked_paths;
import { kind_by_name, is_imported, is_props, is_local_tracked, find_visible_binding } from .compiler.backend.browser.classify_tracked_roots;
import { collect } from .compiler.backend.browser.collect_tracked_paths;

fn binding(name: string, kind: string, visible: bool, callable: bool): ScriptBinding {
    return {
        name: name,
        kind: kind,
        exported: false,
        template_visible: visible,
        callable: callable,
        type_annotation: none,
        span: {
            start: 0,
            end: 0
        }
    };
}
fn script(): ScriptFacts {
    var bindings = list<ScriptBinding>();
    bindings.push(binding("root", "immutable", true, false));
    bindings.push(binding("other", "mutable", true, false));
    return {
        ok: true,
        source_path: "test.ts",
        props: none,
        imports: list<ScriptImport>(),
        bindings: bindings,
        diagnostics: list<ScriptDiagnostic>(),
        state_facts: {
            helpers: list<HelperFacts>(),
            mutations: list<MutationFacts>(),
            aliases: list<AliasFacts>(),
            callback_registrations: list<CallbackRegistrationFacts>()
        }
    };
}
fn imported(name: string): ScriptImport {
    return {
        source: "./module",
        kind: "named",
        imported_name: name,
        local_name: name,
        span: {
            start: 0,
            end: 0
        }
    };
}
fn mutation(name: string, member: ?string): MutationFacts {
    return {
        binding: name,
        kind: "assignment",
        span: {
            start: 0,
            end: 0
        },
        statement_position: true,
        member_path: member,
        inside_callback: false,
        callback_owned_candidate: false
    };
}
fn document(): LirDocument {
    return {
        nodes: list<LirNode>(),
        roots: list<usize>(),
        expressions: list<LirExpressionFacts>()
    };
}
fn table(): TrackedPaths {
    return {
        roots: list<TrackedRoot>(),
        paths: list<TrackedPath>()
    };
}
fn append(source: string, facts: &const ScriptFacts, output: &TrackedPaths): List<usize> {
    const lir = document();
    var ids = list<usize>();
    collect(source.bytes(), {
        start: 0,
        end: source.bytes().len()
    }, facts, &lir, output, &ids);
    return ids;
}
fn expect_kind(facts: &const ScriptFacts, name: string, kind: TrackedKind): void {
    if kind_by_name(facts, name) is actual {
        assert(actual == kind);
    } else {
        assert(false);
    }
}

test "tracking classification gives imports priority over props and locals" {
    var facts = script();
    facts.imports.push(imported("root"));
    facts.props = PropsFacts {
        has_props_export: false,
        props_binding_name: "root",
        props_type_name: none
    };
    facts.state_facts.mutations.push(mutation("root", none));
    expect_kind(&facts, "root", TrackedKind.imported_tracked);
    assert(is_imported(&facts, "root"));
    assert(is_props(&facts, "root"));
    assert(not is_local_tracked(&facts, "root"));
    expect_kind(&facts, "other", TrackedKind.local_tracked);
    assert(kind_label(TrackedKind.imported_tracked) == "imported-tracked");
    assert(kind_label(TrackedKind.prop_tracked) == "prop-tracked");
    assert(kind_label(TrackedKind.local_tracked) == "local-tracked");
}

test "props classification uses the binding name independently of export presence" {
    var facts = script();
    facts.props = PropsFacts {
        has_props_export: false,
        props_binding_name: "props",
        props_type_name: none
    };
    expect_kind(&facts, "props", TrackedKind.prop_tracked);
    facts.props = PropsFacts {
        has_props_export: true,
        props_binding_name: none,
        props_type_name: "Props"
    };
    if kind_by_name(&facts, "props") is kind {
        assert(false);
    }
}

test "local tracking excludes invisible callable and unsupported binding kinds" {
    var facts = script();
    facts.bindings.push(binding("hidden", "mutable", false, false));
    facts.bindings.push(binding("helper", "immutable", true, true));
    facts.bindings.push(binding("function", "function", true, false));
    if kind_by_name(&facts, "hidden") is kind {
        assert(false);
    }
    if kind_by_name(&facts, "helper") is kind {
        assert(false);
    }
    if kind_by_name(&facts, "function") is kind {
        assert(false);
    }
    if kind_by_name(&facts, "missing") is kind {
        assert(false);
    }
    expect_kind(&facts, "root", TrackedKind.local_tracked);
}

test "first visible matching binding decides local tracking" {
    var facts = script();
    facts.bindings = list<ScriptBinding>();
    facts.bindings.push(binding("root", "immutable", false, false));
    facts.bindings.push(binding("root", "immutable", true, true));
    facts.bindings.push(binding("root", "mutable", true, false));
    if find_visible_binding(&facts, "root") is index {
        assert(index == 1);
    } else {
        assert(false);
    }
    assert(not is_local_tracked(&facts, "root"));
}

test "alias targets and whole-binding mutations exclude local tracking" {
    var facts = script();
    facts.state_facts.aliases.push(AliasFacts {
        alias: "copy",
        target: "root",
        kind: "reference",
        span: {
            start: 0,
            end: 0
        }
    });
    assert(not is_local_tracked(&facts, "root"));
    facts.state_facts.mutations.push(mutation("other", "field"));
    expect_kind(&facts, "other", TrackedKind.local_tracked);
    facts.state_facts.mutations.push(mutation("other", none));
    assert(not is_local_tracked(&facts, "other"));
}

test "empty member path counts as member mutation rather than absence" {
    var facts = script();
    facts.state_facts.mutations.push(mutation("root", ""));
    expect_kind(&facts, "root", TrackedKind.local_tracked);
}

test "canonical path chains assign one-based root and parent IDs in encounter order" {
    const facts = script();
    var output = table();
    const ids = append("root . child . value + root.child + other.name", &facts, &output);
    assert(ids.len() == 3);
    assert(ids[0] == 3);
    assert(ids[1] == 2);
    assert(ids[2] == 5);
    assert(output.roots.len() == 2);
    assert(output.paths.len() == 5);
    assert(output.roots[0].id == 1);
    assert(output.roots[1].id == 2);
    assert(output.paths[0].path == "root");
    assert(output.paths[1].path == "root.child");
    assert(output.paths[2].path == "root.child.value");
    if output.paths[0].parent_path_id is id {
        assert(false);
    }
    if output.paths[2].parent_path_id is id {
        assert(id == 2);
    } else {
        assert(false);
    }
    assert(output.paths[4].root_id == 2);
    if output.find_root("other") is id {
        assert(id == 2);
    } else {
        assert(false);
    }
    if output.find_path("root.child") is id {
        assert(id == 2);
    } else {
        assert(false);
    }
}

test "leaf IDs deduplicate without dropping previously appended IDs" {
    const facts = script();
    const lir = document();
    var output = table();
    var ids = list<usize>();
    ids.push(99);
    ids.push(2);
    const source = "root.x + root.x + root.y";
    collect(source.bytes(), {
        start: 0,
        end: source.bytes().len()
    }, &facts, &lir, &output, &ids);
    assert(ids.len() == 3);
    assert(ids[0] == 99);
    assert(ids[1] == 2);
    assert(ids[2] == 3);
    const repeated = append("root.y + root.x", &facts, &output);
    assert(output.paths.len() == 3);
    assert(repeated[0] == 3);
    assert(repeated[1] == 2);
}

test "method calls stop paths before their callable segment" {
    const facts = script();
    var output = table();
    const scalar = append("root.method() + root() + root", &facts, &output);
    assert(scalar.len() == 0);
    assert(output.paths.len() == 0);
    assert(output.roots.len() == 0);
    const ids = append("root.child.run () + root.child.value", &facts, &output);
    assert(ids.len() == 2);
    assert(output.paths[1].path == "root.child");
    assert(output.paths[2].path == "root.child.value");
}

test "optional and computed access stop canonical dotted segments" {
    const facts = script();
    var output = table();
    const ids = append("root?.x + root.x?.y + root[other.child].z", &facts, &output);
    assert(ids.len() == 2);
    assert(output.paths.len() == 4);
    assert(output.paths[1].path == "root.x");
    assert(output.paths[3].path == "other.child");
}

test "bound references use source identity and leave unbound equal text on fallback scanning" {
    const facts = script();
    var lir = document();
    var output = table();
    var ids = list<usize>();
    lir.expressions.push(LirExpressionFacts {
        source: {
            start: 0,
            end: 6
        },
        references: list<LirExpressionReference>()
    });
    const source = "root.x root.x";
    collect(source.bytes(), {
        start: 0,
        end: 6
    }, &facts, &lir, &output, &ids);
    assert(ids.len() == 0);
    assert(output.paths.len() == 0);
    collect(source.bytes(), {
        start: 7,
        end: 13
    }, &facts, &lir, &output, &ids);
    assert(ids.len() == 1);
    assert(ids[0] == 2);
    var references = list<LirExpressionReference>();
    references.push(LirExpressionReference {
        name: "root",
        call: true
    });
    lir.expressions[0] = LirExpressionFacts {
        source: {
            start: 0,
            end: 6
        },
        references: references
    };
    collect(source.bytes(), {
        start: 0,
        end: 6
    }, &facts, &lir, &output, &ids);
    assert(ids.len() == 1);
}

test "legacy scanner preserves quote comment and spread behavior" {
    const facts = script();
    var output = table();
    const ids = append("'root.quoted' + /*root.comment*/ ...root.spread", &facts, &output);
    assert(ids.len() == 3);
    assert(output.paths.len() == 4);
    assert(output.paths[1].path == "root.quoted");
    assert(output.paths[2].path == "root.comment");
    assert(output.paths[3].path == "root.spread");
}

fn detached(): TrackedPaths {
    const facts = script();
    var output = table();
    const source = "root.child.value";
    const ids = append(source, &facts, &output);
    return output;
}
test "tracked tables own names and prefixes independently of input lifetimes" {
    const output = detached();
    assert(output.roots[0].binding_name == "root");
    assert(output.paths[2].path == "root.child.value");
    if output.find_root("missing") is id {
        assert(false);
    }
    if output.find_path("missing") is id {
        assert(false);
    }
}

test "deep path chains create each prefix and parent without recursion" {
    var bytes = list<u8>();
    for byte in "root".bytes() {
        bytes.push(byte);
    }
    var i: usize = 0;
    while i < 256 {
        bytes.push(46);
        bytes.push(120);
        i = i + 1;
    }
    const source = string.from(bytes.view());
    const facts = script();
    var output = table();
    const ids = append(source, &facts, &output);
    assert(output.paths.len() == 257);
    assert(ids.len() == 1);
    assert(ids[0] == 257);
    if output.paths[256].parent_path_id is id {
        assert(id == 256);
    } else {
        assert(false);
    }
}

test "legacy bound scanner keeps quoted paths when the same root is referenced elsewhere" {
    const facts = script();
    var lir = document();
    var output = table();
    var ids = list<usize>();
    const source = "'root.fake' + root.real";
    var references = list<LirExpressionReference>();
    references.push(LirExpressionReference {
        name: "root",
        call: false
    });
    lir.expressions.push(LirExpressionFacts {
        source: {
            start: 0,
            end: source.bytes().len()
        },
        references: references
    });
    collect(source.bytes(), {
        start: 0,
        end: source.bytes().len()
    }, &facts, &lir, &output, &ids);
    assert(ids.len() == 2);
    assert(ids[0] == 2);
    assert(ids[1] == 3);
    assert(output.paths[1].path == "root.fake");
    assert(output.paths[2].path == "root.real");
}

test "identifier scanning preserves ASCII keywords property roots and dollar names" {
    var facts = script();
    facts.bindings.push(binding("await", "immutable", true, false));
    facts.bindings.push(binding("_root", "immutable", true, false));
    facts.bindings.push(binding("$data", "immutable", true, false));
    facts.bindings.push(binding("root2", "immutable", true, false));
    var output = table();
    const ids = append("await.x + _root.v + $data.x + object.root.a + root2.x", &facts, &output);
    assert(ids.len() == 3);
    assert(output.roots.len() == 3);
    assert(output.roots[0].binding_name == "_root");
    assert(output.roots[1].binding_name == "$data");
    assert(output.roots[2].binding_name == "root2");
}
