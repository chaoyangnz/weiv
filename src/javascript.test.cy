import std.mem;
import { emit_string, emit_html_string, ref_name, indent } from .compiler.backend.browser.emit.js_module.write_javascript;
import { decode as entity } from .compiler.backend.browser.emit.js_module.html_entities;
import { rewrite_extension, direct_specifier, should_preserve, emit as emit_imports } from .compiler.backend.browser.emit.js_module.emit_module_imports;
import { ImportOverride, JavaScriptModule } from .compiler.backend.browser.emit.javascript_module;
import { JavaScriptError } from .compiler.backend.browser.emit.javascript_errors;
import { decode } from .compiler.backend.browser.emit.js_module.decode_cell_output;
import { emit } from .compiler.backend.browser.emit.emit_static_module;
import { build } from .compiler.backend.browser.build_component;
import { compile_report, take_unit } from .compiler.compile;
import { ComponentManifests, ComponentSlotManifest } from .compiler.sema.component_manifests;
import { ScriptFacts, ScriptBinding, ScriptImport, ScriptDiagnostic, HelperFacts, MutationFacts, AliasFacts, CallbackRegistrationFacts } from .compiler.sema.script_facts;
import { lower_cells_raw, ScriptBackendError } from .ffi.script_backend;
import { emit as emit_destroy_nodes } from .compiler.backend.browser.emit.js_module.emit_destroy_nodes;

fn quoted(value: string, html: bool): string {
    var out = list<u8>();
    if html {
        emit_html_string(value, &out);
    } else {
        emit_string(value, &out);
    }
    return string.from(out.view());
}
fn facts(): ScriptFacts {
    return {
        ok: true,
        source_path: "test.ts",
        props: none,
        imports: list<ScriptImport>(),
        bindings: list<ScriptBinding>(),
        diagnostics: list<ScriptDiagnostic>(),
        state_facts: {
            helpers: list<HelperFacts>(),
            mutations: list<MutationFacts>(),
            aliases: list<AliasFacts>(),
            callback_registrations: list<CallbackRegistrationFacts>()
        }
    };
}
fn record(kind: string, source: string, local: string, imported: ?string): ScriptImport {
    return {
        source: source,
        kind: kind,
        imported_name: imported,
        local_name: local,
        span: {
            start: 0,
            end: 0
        }
    };
}
fn compiled(template: string, style: string): JavaScriptModule {
    const script = "export interface Props {} export let props: Props; export const value=1;";
    const source = $"<template>{template}</template><script lang=\"ts\">{script}</script><style>{style}</style>";
    const catalog: ComponentManifests = {
        entries: list<ComponentSlotManifest>()
    };
    var report = compile_report(source, "static.weiv", &catalog);
    const unit = take_unit(&report) catch (code) {
        panic("Expected unit");
    };
    const browser = build(unit);
    const overrides = list<ImportOverride>();
    return emit(&browser, &overrides) catch (code) {
        panic("Expected static module");
    };
}
fn reject(template: string): void {
    const script = "export interface Props {} export let props: Props; export const value=1; export const Card={}; export const items=[];";
    const source = $"<template>{template}</template><script lang=\"ts\">{script}</script>";
    const catalog: ComponentManifests = {
        entries: list<ComponentSlotManifest>()
    };
    var report = compile_report(source, "dynamic.weiv", &catalog);
    const unit = take_unit(&report) catch (code) {
        panic("Expected unit");
    };
    const browser = build(unit);
    const overrides = list<ImportOverride>();
    const result = emit(&browser, &overrides) catch (code) {
        assert(code == JavaScriptError.unsupported_template);
        return;
    };
    assert(false);
}

test "nested slot cleanup follows conditional element descendants" {
    const source = "<template><div #if=\"open\"><section><slot>fallback</slot></section></div></template><script lang=\"ts\">let open = true;</script>";
    const catalog: ComponentManifests = {
        entries: list<ComponentSlotManifest>()
    };
    var report = compile_report(source, "nested-slot.weiv", &catalog);
    const unit = take_unit(&report) catch (code) {
        panic("Expected unit");
    };
    const browser = build(unit);
    var output = list<u8>();
    emit_destroy_nodes(&browser.render_tree, &browser.render_tree.roots, &output, 1, "refs");
    assert(string.from(output.view()).contains("__destroy_slot_"));
}

test "JavaScript literals escape the exact reference characters and preserve UTF-8" {
    assert(quoted("a\"b\\c\n\r\t🌱", false) == "\"a\\\"b\\\\c\\n\\r\\t🌱\"");
    assert(quoted("", false) == "\"\"");
}

test "HTML named entities include multi-scalar and supplementary values" {
    assert(quoted("&amp;&quot;&apos;&lt;&gt;&nbsp;", true) == "\"&\\\"'<> \"");
    assert(quoted("&NotEqualTilde;&Afr;", true) == "\"≂̸𝔄\"");
    if entity("zwnj") is value {
        assert(value == "‌");
    } else {
        assert(false);
    }
    if entity("unknown") is value {
        assert(false);
    }
}

test "numeric entities preserve hex decimal signs underscores and invalid scalar behavior" {
    assert(quoted("&#65;&#x41;&#X1F331;", true) == "\"AA🌱\"");
    assert(quoted("&#0;&#xD800;&#x110000;", true) == "\"���\"");
    assert(quoted("&#-1;&#2097152;&#xZZ;", true) == "\"&#-1;&#2097152;&#xZZ;\"");
    assert(quoted("&#+65;&#6_5;&#-0;", true) == "\"AA�\"");
}

test "entity decoding is one pass and requires a terminating semicolon" {
    assert(quoted("&amp;lt; &unknown; &amp", true) == "\"&lt; &unknown; &amp\"");
}

test "reference names and indentation use stable decimal IDs and two spaces" {
    assert(ref_name(42) == "__ref_42");
    var out = list<u8>();
    indent(3, &out);
    assert(string.from(out.view()) == "      ");
}

test "import specifier rewrites match exact suffixes rather than query extensions" {
    assert(rewrite_extension("./a.ts") == "./a.js");
    assert(rewrite_extension("./a.mts") == "./a.mjs");
    assert(rewrite_extension("./a.ts?raw") == "./a.ts?raw");
    assert(rewrite_extension("./a.TS") == "./a.TS");
    assert(direct_specifier("./Card.weiv") == "./Card.mjs");
    assert(rewrite_extension("./Card.weiv") == "./Card.weiv");
}

test "imports preserve source order kinds aliases and first override" {
    var script = facts();
    script.imports.push(record("side_effect", "./side.ts", "", none));
    script.imports.push(record("default", "./value.mts", "value", none));
    script.imports.push(record("namespace", "./ns.ts", "ns", none));
    script.imports.push(record("named", "./named.ts", "local", "original"));
    script.imports.push(record("default", "./Card.weiv", "Card", none));
    var overrides = list<ImportOverride>();
    overrides.push(ImportOverride {
        source: "./value.mts",
        target: "./override.js"
    });
    overrides.push(ImportOverride {
        source: "./value.mts",
        target: "ignored"
    });
    assert(emit_imports(&script, &overrides) == "import \"./side.js\";\nimport __weiv_import_value from \"./override.js\";\nimport * as __weiv_import_ns from \"./ns.js\";\nimport { original as __weiv_import_local } from \"./named.js\";\nimport * as Card from \"./Card.mjs\";\n\n");
}

test "type-only imports use the first same-name binding without a visibility condition" {
    var script = facts();
    const imported = record("named", "./a.ts", "T", "T");
    script.bindings.push(ScriptBinding {
        name: "T",
        kind: "type_only",
        exported: false,
        template_visible: false,
        callable: false,
        type_annotation: none,
        span: {
            start: 0,
            end: 0
        }
    });
    assert(not should_preserve(&imported, &script));
    const side = record("side_effect", "./a.ts", "T", none);
    assert(should_preserve(&side, &script));
}

test "missing named-import names emit nothing without a trailing newline" {
    var script = facts();
    script.imports.push(record("named", "./a.ts", "x", none));
    const overrides = list<ImportOverride>();
    assert(emit_imports(&script, &overrides) == "");
}

test "lowering response returns owned code and preserves known failure categories" {
    const result = decode("{\"code\":\"let a=1;\",\"error\":null}") catch (code) {
        panic("Expected code");
    };
    assert(result == "let a=1;");
    const failed = decode("{\"code\":\"\",\"error\":\"dynamic_eval\"}") catch (code) {
        assert(code == JavaScriptError.cell_dynamic_eval_unsupported);
        return;
    };
    assert(false);
}

test "malformed lowering response is not treated as empty emitted code" {
    const result = decode("{\"code\":\"\"}") catch (code) {
        assert(code == JavaScriptError.invalid_backend_response);
        return;
    };
    assert(false);
}

test "static module owns setup exports DOM functions scope and CSS beyond compilation lifetime" {
    const output = compiled("<p title=\"a &amp; b\">Hello &copy;</p>", "p{color:red}");
    assert(output.scope_id.bytes().len() == 17);
    assert(output.css.bytes().len() > 0);
    assert(mem.contains(output.code.bytes(), "export function mount(target".bytes()));
    assert(mem.contains(output.code.bytes(), "function setup(".bytes()));
    assert(mem.contains(output.code.bytes(), "Hello ©".bytes()));
    assert(mem.contains(output.code.bytes(), "a & b".bytes()));
}

test "dynamic template nodes and effects return explicit unsupported-template errors" {
    reject("{{value}}");
    reject("<p bind:title=\"value\"/>");
    reject("<p @click=\"value\"/>");
    reject("<p #if=\"value\"/>");
    reject("<p #for=\"item in items\"/>");
    reject("<Card/>");
    reject("<slot/>");
}

test "empty and multiple static roots produce complete modules" {
    const empty = compiled("", "");
    const roots = compiled("text<p/><br>", "");
    assert(mem.contains(empty.code.bytes(), "return fragment;".bytes()));
    assert(mem.contains(roots.code.bytes(), "fragment.append(document.createTextNode(\"text\"))".bytes()));
}

test "SVG and foreignObject namespace branches are emitted with root scope markers" {
    const output = compiled("<svg><circle cx=\"1\"/><foreignObject><div>HTML</div></foreignObject></svg>", "");
    assert(mem.contains(output.code.bytes(), "document.createElementNS(\"http://www.w3.org/2000/svg\", \"svg\")".bytes()));
    assert(mem.contains(output.code.bytes(), "localName !== \"foreignObject\"".bytes()));
}

test "raw lowering transport rejects embedded NUL in every input position" {
    expect_nul(0);
    expect_nul(1);
    expect_nul(2);
    expect_nul(3);
}

fn expect_nul(position: i32): void {
    const bytes: [1]u8 = [0];
    const bad = string.from(bytes[..1]);
    if position == 0 {
        const value = lower_cells_raw(bad, "x.ts", "[]", "") catch (code) {
            assert(code == ScriptBackendError.embedded_nul);
            return;
        };
    } else if position == 1 {
        const value = lower_cells_raw("", bad, "[]", "") catch (code) {
            assert(code == ScriptBackendError.embedded_nul);
            return;
        };
    } else if position == 2 {
        const value = lower_cells_raw("", "x.ts", bad, "") catch (code) {
            assert(code == ScriptBackendError.embedded_nul);
            return;
        };
    } else {
        const value = lower_cells_raw("", "x.ts", "[]", bad) catch (code) {
            assert(code == ScriptBackendError.embedded_nul);
            return;
        };
    }
    assert(false);
}

test "reference import output preserves unescaped specifiers and empty component side-effect aliases" {
    var script = facts();
    const overrides = list<ImportOverride>();
    script.imports.push(record("side_effect", "./quote\".ts", "", none));
    assert(emit_imports(&script, &overrides) == "import \"./quote\".js\";\n\n");
    script.imports = list<ScriptImport>();
    script.imports.push(record("side_effect", "./Card.weiv", "", none));
    assert(emit_imports(&script, &overrides) == "import * as  from \"./Card.mjs\";\n\n");
}

test "deep static DOM emission uses the render work stack" {
    var bytes = list<u8>();
    var i: usize = 0;
    while i < 256 {
        for byte in "<a>".bytes() {
            bytes.push(byte);
        }
        i = i + 1;
    }
    for byte in "bottom".bytes() {
        bytes.push(byte);
    }
    i = 0;
    while i < 256 {
        for byte in "</a>".bytes() {
            bytes.push(byte);
        }
        i = i + 1;
    }
    const output = compiled(string.from(bytes.view()), "");
    assert(mem.contains(output.code.bytes(), "const __ref_255 = ".bytes()));
    assert(mem.contains(output.code.bytes(), "const __ref_0 = ".bytes()));
    assert(mem.contains(output.code.bytes(), "document.createTextNode(\"bottom\")".bytes()));
}
