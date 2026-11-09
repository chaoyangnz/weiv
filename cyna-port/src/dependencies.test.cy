import std.io;
import { ScriptFacts, ScriptBinding, ScriptImport, ScriptDiagnostic, HelperFacts, MutationFacts, AliasFacts, CallbackRegistrationFacts } from .compiler.sema.script_facts;
import { LirDocument, LirNode, LirExpressionFacts, LirExpressionReference } from .compiler.lower.lir;
import { DependencyList } from .compiler.backend.browser.dependencies;
import { DependencyOptions, collect_expression, collect_node, retain_visible } from .compiler.backend.browser.collect_dependencies;
import { parse } from .compiler.parser.template.parse;
import { normalize } from .compiler.parser.template.normalize;
import { lower as lower_lir } from .compiler.lower.lower_template;
import { lower as render } from .compiler.backend.browser.render_tree.lower;
import { TemplateBindings, ComponentRef, ExpressionFacts, TemplateBindingDiagnostic } from .compiler.sema.template_bindings;
import { SlotManifest, SlotEntry } from .compiler.sema.slot_manifest;

fn facts(): ScriptFacts {
    return {
        ok: true,
        source_path: "test.ts",
        props: none,
        bindings: list<ScriptBinding>(),
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
fn add(script: &ScriptFacts, name: string, callable: bool): void {
    script.bindings.push(ScriptBinding {
        name: name,
        kind: "immutable",
        exported: false,
        template_visible: true,
        callable: callable,
        type_annotation: none,
        span: {
            start: 0,
            end: 0
        }
    });
}
fn imported(script: &ScriptFacts, name: string): void {
    script.imports.push(ScriptImport {
        source: "module",
        kind: "named",
        imported_name: name,
        local_name: name,
        span: {
            start: 0,
            end: 0
        }
    });
}
fn one(name: string): List<string> {
    var result = list<string>();
    result.push(name);
    return result;
}
fn two(a: string, b: string): List<string> {
    var result = one(a);
    result.push(b);
    return result;
}
fn helper(name: string, reads: List<string>, calls: List<string>): HelperFacts {
    return {
        name: name,
        kind: "function",
        span: {
            start: 0,
            end: 0
        },
        reads: reads,
        writes: list<string>(),
        calls: calls,
        async_flag: false,
        returns_expression_only: true,
        contains_external_reads: false,
        contains_side_effects: false
    };
}
fn empty_lir(): LirDocument {
    return {
        nodes: list<LirNode>(),
        roots: list<usize>(),
        expressions: list<LirExpressionFacts>()
    };
}
fn deps(): DependencyList {
    return {
        items: list<string>()
    };
}
fn options(retain: bool): DependencyOptions {
    return {
        retain_imported_calls: retain
    };
}
fn expression(source: string, script: &const ScriptFacts, retain: bool): DependencyList {
    const document = empty_lir();
    const locals = list<string>();
    var output = deps();
    collect_expression(source.bytes(), {
        start: 0,
        end: source.bytes().len()
    }, script, &document, &locals, &output, options(retain));
    return output;
}
fn expect(output: &const DependencyList, expected: string): void {
    var bytes = list<u8>();
    var i: usize = 0;
    while i < output.items.len() {
        if i > 0 {
            bytes.push(44);
        }
        for byte in output.items[i].bytes() {
            bytes.push(byte);
        }
        i = i + 1;
    }
    const actual = string.from(bytes.view());
    if actual != expected {
        io.write_line($"expected {expected}, got {actual}");
    }
    assert(actual == expected);
}
fn node(source: string, script: &const ScriptFacts, locals: &const List<string>, retain: bool): DependencyList {
    const raw = parse(source.bytes()) catch (code) {
        panic("Expected template");
    };
    const normalized = normalize(&raw) catch (code) {
        panic("Expected normalization");
    };
    const bindings: TemplateBindings = {
        component_refs: list<ComponentRef>(),
        expressions: list<ExpressionFacts>(),
        diagnostics: list<TemplateBindingDiagnostic>(),
        own_slot_manifest: SlotManifest {
            entries: list<SlotEntry>()
        }
    };
    const lir = lower_lir(source.bytes(), &raw, &normalized, &bindings) catch (code) {
        panic("Expected LIR");
    };
    const tree = render(&lir);
    var output = deps();
    collect_node(source.bytes(), script, &lir, &tree, tree.roots[0], locals, &output, options(retain));
    return output;
}

test "fallback dependencies preserve first encounter order and ignore unknown properties" {
    var script = facts();
    add(&script, "a", false);
    add(&script, "b", false);
    add(&script, "method", false);
    const output = expression("a.x + b + a + unknown.method()", &script, false);
    expect(&output, "a,b");
}

test "imported call policy affects direct calls but retains imported values" {
    var script = facts();
    add(&script, "load", true);
    imported(&script, "load");
    const omitted = expression("load()", &script, false);
    expect(&omitted, "");
    const retained = expression("load()", &script, true);
    expect(&retained, "load");
    const value = expression("load", &script, false);
    expect(&value, "load");
}

test "helper reads precede depth-first calls and direct references follow expansion" {
    var script = facts();
    add(&script, "f", true);
    add(&script, "g", true);
    add(&script, "tail", false);
    script.state_facts.helpers.push(helper("f", two("first", "external"), two("g", "tail")));
    script.state_facts.helpers.push(helper("g", one("nested"), one("unknown")));
    const output = expression("f() + tail", &script, false);
    expect(&output, "f,first,external,g,nested,unknown,tail");
}

test "self and mutual recursion stop on a path-local trail" {
    var script = facts();
    add(&script, "a", true);
    add(&script, "b", true);
    script.state_facts.helpers.push(helper("a", one("x"), two("a", "b")));
    script.state_facts.helpers.push(helper("b", one("y"), one("a")));
    const output = expression("a() + b()", &script, true);
    expect(&output, "a,x,b,y");
}

test "helper call imports remain dependencies independently of direct-call policy" {
    var script = facts();
    add(&script, "f", true);
    add(&script, "load", true);
    imported(&script, "load");
    script.state_facts.helpers.push(helper("f", list<string>(), one("load")));
    const output = expression("f() + load()", &script, false);
    expect(&output, "f,load");
}

test "noncallable bindings and missing helper facts are not expanded" {
    var script = facts();
    add(&script, "value", false);
    add(&script, "f", true);
    script.state_facts.helpers.push(helper("value", one("not-read"), list<string>()));
    const output = expression("value() + f()", &script, true);
    expect(&output, "value,f");
}

test "first visible binding and first helper record decide expansion" {
    var script = facts();
    add(&script, "f", true);
    add(&script, "f", false);
    script.state_facts.helpers.push(helper("f", one("first"), list<string>()));
    script.state_facts.helpers.push(helper("f", one("second"), list<string>()));
    const output = expression("f()", &script, false);
    expect(&output, "f,first");
}

test "bound facts preserve source identity call upgrades and reference ordering" {
    var script = facts();
    add(&script, "a", false);
    add(&script, "f", true);
    script.state_facts.helpers.push(helper("f", one("inner"), list<string>()));
    var lir = empty_lir();
    var references = list<LirExpressionReference>();
    references.push(LirExpressionReference {
        name: "f",
        call: true
    });
    references.push(LirExpressionReference {
        name: "a",
        call: false
    });
    lir.expressions.push(LirExpressionFacts {
        source: {
            start: 0,
            end: 7
        },
        references: references
    });
    const source = "a + f() a + f()";
    const locals = list<string>();
    var bound = deps();
    var fallback = deps();
    collect_expression(source.bytes(), {
        start: 0,
        end: 7
    }, &script, &lir, &locals, &bound, options(false));
    collect_expression(source.bytes(), {
        start: 8,
        end: 15
    }, &script, &lir, &locals, &fallback, options(false));
    expect(&bound, "f,inner,a");
    expect(&fallback, "a,f,inner");
}

test "explicit locals admit otherwise invisible names and stable visible compaction removes them" {
    var script = facts();
    add(&script, "visible", false);
    const source = "item + visible";
    const lir = empty_lir();
    const locals = one("item");
    var output = deps();
    collect_expression(source.bytes(), {
        start: 0,
        end: source.bytes().len()
    }, &script, &lir, &locals, &output, options(false));
    expect(&output, "item,visible");
    retain_visible(&script, &output);
    expect(&output, "visible");
}

test "visible retention preserves ordering and existing duplicate entries" {
    var script = facts();
    add(&script, "a", false);
    add(&script, "b", false);
    var output = deps();
    output.items.push("gone");
    output.items.push("b");
    output.items.push("a");
    output.items.push("b");
    retain_visible(&script, &output);
    expect(&output, "b,a,b");
}

test "HTML event dependencies are omitted while component events and projected content are included" {
    var script = facts();
    add(&script, "html", true);
    add(&script, "child", true);
    add(&script, "value", false);
    add(&script, "text", false);
    const locals = list<string>();
    const output = node("<div @click=\"html\" bind:title=\"value\"><Card @pick=\"child\">{{text}}</Card></div>", &script, &locals, false);
    expect(&output, "value,child,text");
}

test "loop locals apply after the iterable and expire before following siblings" {
    var script = facts();
    add(&script, "items", false);
    const locals = list<string>();
    const output = node("<div><i #for=\"item in items\">{{item}}</i>{{item}}</div>", &script, &locals, false);
    expect(&output, "items,item");
    assert(locals.len() == 0);
    const sibling = node("<div><i #for=\"item in items\"/>{{item}}</div>", &script, &locals, false);
    expect(&sibling, "items");
}

test "conditional branches and slot fallback contribute in traversal order" {
    var script = facts();
    add(&script, "condition", false);
    add(&script, "yes", false);
    add(&script, "no", false);
    const locals = list<string>();
    const output = node("<div><p #if=\"condition\">{{yes}}</p><p #else><slot>{{no}}</slot></p></div>", &script, &locals, false);
    expect(&output, "condition,yes,no");
}

test "legacy fallback scanner admits quote and comment tokens but skips keywords and property names" {
    var script = facts();
    add(&script, "a", false);
    add(&script, "b", false);
    add(&script, "await", false);
    add(&script, "value", false);
    const output = expression("'a' + /*b*/ await x + obj.value + [...a]", &script, false);
    expect(&output, "a,b");
}

fn detached(): DependencyList {
    var script = facts();
    add(&script, "helper", true);
    script.state_facts.helpers.push(helper("helper", one("owned"), list<string>()));
    return expression("helper()", &script, false);
}
test "dependency results own helper read names beyond input lifetime" {
    const output = detached();
    expect(&output, "helper,owned");
}

test "deep helper expansion uses a work stack without native recursion" {
    var script = facts();
    var i: usize = 0;
    while i < 256 {
        const name = $"f{i}";
        add(&script, name, true);
        const next = i + 1;
        const called = $"f{next}";
        script.state_facts.helpers.push(helper(name, list<string>(), one(called)));
        i = i + 1;
    }
    const output = expression("f0()", &script, false);
    assert(output.items.len() == 257);
    assert(output.items[0] == "f0");
    assert(output.items[256] == "f256");
}

test "component dependencies follow split effects and merged provision order" {
    var script = facts();
    add(&script, "a", false);
    add(&script, "b", false);
    add(&script, "c", false);
    add(&script, "event", false);
    add(&script, "binding", false);
    const locals = list<string>();
    const output = node("<Card @pick=\"event\" bind:title=\"binding\"><p slot:head>{{a}}</p>{{b}}<i slot:head>{{c}}</i></Card>", &script, &locals, false);
    expect(&output, "binding,event,a,c,b");
}

test "deep node collection scopes are iterative and do not mutate supplied locals" {
    var bytes = list<u8>();
    for byte in "<div>".bytes() {
        bytes.push(byte);
    }
    var i: usize = 0;
    while i < 256 {
        for byte in "<i #for=\"item in items\">".bytes() {
            bytes.push(byte);
        }
        i = i + 1;
    }
    for byte in "{{item + outer}}".bytes() {
        bytes.push(byte);
    }
    i = 0;
    while i < 256 {
        for byte in "</i>".bytes() {
            bytes.push(byte);
        }
        i = i + 1;
    }
    for byte in "</div>".bytes() {
        bytes.push(byte);
    }
    var script = facts();
    add(&script, "items", false);
    const locals = one("outer");
    const output = node(string.from(bytes.view()), &script, &locals, false);
    expect(&output, "items,item,outer");
    assert(locals.len() == 1);
    assert(locals[0] == "outer");
}

test "legacy name-only callable lookup expands script helpers shadowed by loop locals" {
    var script = facts();
    add(&script, "items", false);
    add(&script, "f", true);
    add(&script, "a", false);
    script.state_facts.helpers.push(helper("f", one("a"), list<string>()));
    const locals = list<string>();
    const output = node("<i #for=\"f in items\">{{f()}}</i>", &script, &locals, false);
    expect(&output, "items,f,a");
}
