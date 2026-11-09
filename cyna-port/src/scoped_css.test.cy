import { hash, compute } from .compiler.backend.browser.compute_scope_id;
import { rewrite, emit, append_diagnostics, CssError } from .compiler.backend.browser.emit.emit_scoped_css;
import { build } from .compiler.backend.browser.build_component;
import { BrowserComponent } from .compiler.backend.browser.component;
import { compile_report, take_unit } from .compiler.compile;
import { ComponentUnit } from .compiler.component_unit;
import { ComponentManifests, ComponentSlotManifest } from .compiler.sema.component_manifests;
import { CompilationDiagnostic, CompilationStage, SourceOrigin } from .compiler.diagnostics;

fn rewritten(css: string): string {
    return rewrite(css.bytes(), "[s]") catch (code) {
        panic("Expected stylesheet");
    };
}
fn invalid(css: string): void {
    const result = rewrite(css.bytes(), "[s]") catch (code) {
        assert(code == CssError.unterminated_rule);
        return;
    };
    assert(false);
}
fn component(source: string, path: string): BrowserComponent {
    const catalogs: ComponentManifests = {
        entries: list<ComponentSlotManifest>()
    };
    var report = compile_report(source, path, &catalogs);
    const unit = take_unit(&report) catch (code) {
        panic("Expected unit");
    };
    return build(unit);
}
fn styled(css: string): BrowserComponent {
    const template = "<p>{{value}}</p>";
    const script = "export interface Props {} export let props: Props; export const value=1;";
    const source = $"<template>{template}</template><script lang=\"ts\">{script}</script><style>{css}</style>";
    return component(source, "css.weiv");
}

test "Wyhash matches all published Zig seed vectors including long inputs" {
    assert(hash("".bytes(), 0) == 0x0409638ee2bde459);
    assert(hash("a".bytes(), 1) == 0xa8412d091b5fe0a9);
    assert(hash("abc".bytes(), 2) == 0x32dd92e4b2915153);
    assert(hash("message digest".bytes(), 3) == 0x8619124089a3a16b);
    assert(hash("abcdefghijklmnopqrstuvwxyz".bytes(), 4) == 0x7a43afb61d7f5f40);
    assert(hash("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789".bytes(), 5) == 0xff42329b90e50d58);
    assert(hash("12345678901234567890123456789012345678901234567890123456789012345678901234567890".bytes(), 6) == 0xc39cab13b115aad3);
}

test "scope IDs keep uppercase zero padding and exact path byte identity" {
    assert(compute("") == "w0409638EE2BDE459");
    assert(compute("component.weiv").bytes().len() == 17);
    assert(compute("./a.weiv") != compute("a.weiv"));
    assert(compute("A.weiv") != compute("a.weiv"));
    assert(compute("组件/🌱.weiv") == "wD8C71A0166B61563");
}

test "empty whitespace and top-level comments survive unchanged" {
    assert(rewritten("") == "");
    assert(rewritten(" \t\n/* { quoted } */\r") == " \t\n/* { quoted } */\r");
    assert(rewritten("/* unterminated") == "/* unterminated");
}

test "type universal class ID and attribute selector roots retain exact insertion positions" {
    assert(rewritten("p.active {color:red}") == "p[s].active, [s] p.active {color:red}");
    assert(rewritten("* > a{}") == "*[s] > a, [s] * > a {}");
    assert(rewritten(".x:hover{}") == "[s].x:hover, [s] .x:hover {}");
    assert(rewritten("#app{}") == "[s]#app, [s] #app {}");
    assert(rewritten("[role=button]{}") == "[s][role=button], [s] [role=button] {}");
    assert(rewritten("custom-element::part(x){}") == "custom-element[s]::part(x), [s] custom-element::part(x) {}");
}

test "selector commas split only outside parentheses and brackets" {
    assert(rewritten("a, :is(.x,.y), [data-x=\"a,b\"] { x:1; }") == "a[s], [s] a, [s]:is(.x,.y), [s] :is(.x,.y), [s][data-x=\"a,b\"], [s] [data-x=\"a,b\"] { x:1; }");
    assert(rewritten(", a, , {}") == "a[s], [s] a {}");
}

test "whole global selectors unwrap while mixed global selectors stay scoped" {
    assert(rewritten(":global( .x ){}") == ".x {}");
    assert(rewritten(":global(:is(a,b)), p{}") == ":is(a,b), p[s], [s] p {}");
    assert(rewritten(":global(.x) .y{}") == "[s]:global(.x) .y, [s] :global(.x) .y {}");
    assert(rewritten(":global(){}") == "[s]:global(), [s] :global() {}");
}

test "media supports and layer blocks recurse and retain header spelling" {
    assert(rewritten("@media (min-width: 1px){p{a:b}}") == "@media (min-width: 1px){p[s], [s] p {a:b}}");
    assert(rewritten("@supports (display:grid){@layer x{.a{}}}") == "@supports (display:grid){@layer x{[s].a, [s] .a {}}}");
    assert(rewritten("@layer reset;") == "@layer reset;");
}

test "keyframes font-face and unsupported at-rule blocks preserve raw contents" {
    assert(rewritten("@keyframes k{from{opacity:0}to{opacity:1}}") == "@keyframes k{from{opacity:0}to{opacity:1}}");
    assert(rewritten("@font-face{font-family:x;src:url(x)}") == "@font-face{font-family:x;src:url(x)}");
    assert(rewritten("@container x{p{color:red}}") == "@container x{p{color:red}}");
}

test "quoted braces escapes and at-rule punctuation do not terminate blocks" {
    assert(rewritten("p {content:\"}\";other:'{';}") == "p[s], [s] p {content:\"}\";other:'{';}");
    assert(rewritten("@import url(\"a;b{c}\");p{}") == "@import url(\"a;b{c}\");p[s], [s] p {}");
    assert(rewritten("p {content:\"\\\"}\";}") == "p[s], [s] p {content:\"\\\"}\";}");
}

test "unterminated headers selectors and blocks are typed CSS failures" {
    invalid("p");
    invalid("p {");
    invalid("p {x:\"unterminated}");
    invalid("@media x");
    invalid("@media x{p{}");
    invalid("p[data-x=\"{\"]");
}

test "legacy scanner counts comment braces inside declaration blocks" {
    invalid("p { /* } */ color:red; }");
}

test "legacy at-rule prefix matching recurses even on media-prefixed unknown names" {
    assert(rewritten("@mediax{p{}}") == "@mediax{p[s], [s] p {}}");
}

test "browser assembly owns source semantic render and region artifacts after report destruction" {
    const value = component("<template>{{x}}</template><script lang=\"ts\">export interface Props {} export let props: Props; export const x=1;</script>", "owned.weiv");
    assert(value.unit.source_path == "owned.weiv");
    assert(value.unit.script.facts.ok);
    assert(value.render_tree.nodes.len() == 1);
    assert(value.region_graph.regions.len() == 1);
    assert(value.region_graph.regions[0].dependency_names[0] == "x");
    assert(value.unit.lir_document.expressions[0].references[0].name == "x");
    const css = emit(&value.unit) catch (code) {
        panic("Expected no CSS");
    };
    assert(css == "");
}

test "component CSS uses the retained source path and style content" {
    const value = styled("p{color:red}");
    const css = emit(&value.unit) catch (code) {
        panic("Expected CSS");
    };
    const id = compute("css.weiv");
    const selector = $"[data-weiv-scope=\"{id}\"]";
    const body = " {color:red}";
    const expected = $"p{selector}, {selector} p{body}";
    assert(css == expected);
}

test "CSS diagnostics append exact fatal emit code and full-file style coordinates" {
    const value = styled("p {");
    var diagnostics = list<CompilationDiagnostic>();
    diagnostics.push(CompilationDiagnostic {
        stage: CompilationStage.binding,
        origin: SourceOrigin.template,
        severity: "info",
        code: "old",
        message: "old",
        span: none,
        fatal: false
    });
    append_diagnostics(&value.unit, &diagnostics);
    assert(diagnostics.len() == 2);
    const diagnostic = &diagnostics[1];
    assert(diagnostic.stage == CompilationStage.emit);
    assert(diagnostic.origin == SourceOrigin.file);
    assert(diagnostic.code == "style.unterminated_rule");
    assert(diagnostic.message == "Unterminated scoped style rule");
    assert(diagnostic.fatal);
    if diagnostic.span is span {
        if value.unit.sfc_document.style is style {
            assert(span.start == style.content_span.start);
            assert(span.end == style.content_span.end);
        } else {
            assert(false);
        }
    } else {
        assert(false);
    }
}

test "valid empty and absent styles append no diagnostics" {
    const empty = styled("");
    const valid = styled("p{}");
    var diagnostics = list<CompilationDiagnostic>();
    const absent = component("<template></template><script lang=\"ts\">export interface Props {} export let props: Props;</script>", "absent.weiv");
    append_diagnostics(&empty.unit, &diagnostics);
    append_diagnostics(&valid.unit, &diagnostics);
    append_diagnostics(&absent.unit, &diagnostics);
    assert(diagnostics.len() == 0);
}

test "deeply nested CSS group rewriting uses an explicit stack" {
    var bytes = list<u8>();
    var i: usize = 0;
    while i < 256 {
        for byte in "@media x{".bytes() {
            bytes.push(byte);
        }
        i = i + 1;
    }
    for byte in "p{x:y}".bytes() {
        bytes.push(byte);
    }
    i = 0;
    while i < 256 {
        bytes.push(125);
        i = i + 1;
    }
    const output = rewrite(bytes.view(), "[s]") catch (code) {
        panic("Expected deep CSS");
    };
    assert(output.bytes().len() == bytes.len() + 11);
}
