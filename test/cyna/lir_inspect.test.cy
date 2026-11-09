import { format } from .compiler.inspect.lir;
import { compile_report } from .compiler.compile;
import { ComponentManifests, ComponentSlotManifest } from .compiler.sema.component_manifests;
import { cwd } from std.process;
import { collect } from .compiler.project.collect_component_graph;
import { component_manifests } from .compiler.project.build_project;
import { take_unit } from .compiler.compile;
import { build as build_browser } from .compiler.backend.browser.build_component;
import { format as format_render_tree } from .compiler.inspect.render_tree;
import { format as format_ast } from .compiler.inspect.ast;
import { format as format_sir } from .compiler.inspect.sir;
import std.fs;

test "AST and SIR inspectors format repository component as reference text" {
    const directory = cwd() catch (code) {
        panic("Expected current directory");
    };
    const path = $"{directory}/test/examples/basic/basic-counter.weiv";
    const source = fs.read_file(path) catch (code) {
        panic("Expected counter fixture");
    };
    const manifests: ComponentManifests = {
        entries: list<ComponentSlotManifest>()
    };
    const report = compile_report(source, path, &manifests);
    if report.sfc_document is sfc {
        if report.template_document is document {
            const actual = format_ast(source, &document, &sfc, path);
            const expected = $"AST source={path}\nsfc\n  template content=[10..253]\n  script content=[284..544]\n  style content=[562..660]\ntemplate-ast roots=1\n  element <section> attrs=1 directives=0 children=4 [3..242]\n    attr class=\"counter-card\" [12..32]\n    element <h2> attrs=0 directives=0 children=1 [38..64]\n      interpolation `props.title` [42..59]\n    element <p> attrs=0 directives=0 children=2 [70..103]\n      text `Current count: ` [73..88]\n      interpolation `count` [88..99]\n    element <p> attrs=0 directives=0 children=2 [108..139]\n      text `Doubled: ` [111..120]\n      interpolation `doubled()` [120..135]\n    element <button> attrs=0 directives=2 children=1 [145..229]\n      directive on:click=\"increment\"\n      directive bind:disabled=\"count >= limit\"\n      text `\n      Increment\n    ` [199..220]\n";
            assert(actual == expected);
        } else {
            panic("Expected template AST");
        }
    } else {
        panic("Expected SFC document");
    }
    if report.script is script {
        if report.template_bindings is bindings {
            const expected = $"SIR source={path}\nscript\n  ok: true\n  props export: true\n  props type: Props\n  props binding: props\n  imports: 0\n  bindings: 6\n    - Props kind=type_only visible=false callable=false\n    - props kind=mutable visible=true callable=false\n    - count kind=mutable visible=true callable=false\n    - limit kind=mutable visible=true callable=false\n    - doubled kind=function visible=true callable=true\n    - increment kind=function visible=true callable=true\n  diagnostics: 0\nbinding\n  component refs: 0\n  diagnostics: 0\n";
            assert(format_sir(path, &script.facts, &bindings) == expected);
        } else {
            panic("Expected template bindings");
        }
    } else {
        panic("Expected script facts");
    }
}

test "LIR inspector formats repository slot fixture as reference text" {
    const directory = cwd() catch (code) {
        panic("Expected current directory");
    };
    const path = $"{directory}/test/examples/slots/Card.weiv";
    const source = fs.read_file(path) catch (code) {
        panic("Expected slot fixture");
    };
    const manifests: ComponentManifests = {
        entries: list<ComponentSlotManifest>()
    };
    const report = compile_report(source, path, &manifests);
    if report.lir_document is document {
        if report.sfc_document is sfc {
            const bytes = source.bytes();
            const template = string.from(bytes[sfc.template.content_span.start..sfc.template.content_span.end]);
            const actual = format(template, &document);
            assert(actual == "LIR\n  element <section>\n    attr class=\"card\"\n    element <header>\n      attr class=\"card__header\"\n      slot name=\"header\"\n        element <h2>\n          attr class=\"card__fallback-title\"\n          text `Untitled`\n    element <div>\n      attr class=\"card__body\"\n      slot <default>\n        element <p>\n          attr class=\"card__fallback-body\"\n          text `No body content.`\n");
            return;
        }
    }
    panic("Expected complete LIR");
}

test "render-tree inspector formats imported component and slots as reference text" {
    const directory = cwd() catch (code) {
        panic("Expected current directory");
    };
    const root = $"{directory}/test/examples/slots";
    const path = $"{root}/CardUsage.weiv";
    const graph = collect(root, path) catch (code) {
        panic("Expected component graph");
    };
    const manifests = component_manifests(&graph, path) catch (code) {
        panic("Expected imported manifests");
    };
    const node = &graph.nodes[0];
    var report = compile_report(node.source, path, &manifests);
    const unit = take_unit(&report) catch (code) {
        panic("Expected complete component");
    };
    const browser = build_browser(unit);
    const bytes = node.source.bytes();
    const span = browser.unit.sfc_document.template.content_span;
    const template = string.from(bytes[span.start..span.end]);
    const actual = format_render_tree(template, &browser.render_tree);
    assert(actual == "render-tree next_ref_id=9\ncomponent refs=[6,7] handle=8 <Card> binds=0 events=0 slots=2\n  slot-provision name=header\n    element ref=1 <h2> attrs=1 binds=0 events=0\n      interpolation ref=0 expr=props.title\n    element ref=3 <p> attrs=1 binds=0 events=0\n      interpolation ref=2 expr=props.eyebrow\n  slot-provision name=default\n    element ref=5 <p> attrs=1 binds=0 events=0\n      interpolation ref=4 expr=props.body\n");
}
