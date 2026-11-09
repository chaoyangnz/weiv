import { Span } from .compiler.source;
import { compile_report, take_unit, TakeUnitError } from .compiler.compile;
import { ComponentCompileReport, ComponentUnit } from .compiler.component_unit;
import { CompilationDiagnostic, CompilationStage, SourceOrigin } from .compiler.diagnostics;
import { ComponentManifests, ComponentSlotManifest } from .compiler.sema.component_manifests;
import { SlotManifest, SlotEntry } from .compiler.sema.slot_manifest;
import { map_span } from .compiler.map_diagnostic_span;
import { text } from .compiler.sema.binding_context;

fn input(template: string, script: string): string {
    const style = "p { color: red }";
    return $"<template>{template}</template><script lang=\"ts\">{script}</script><style>{style}</style>";
}
fn valid_input(template: string): string {
    return input(template, "export interface Props {} export let props: Props; export const value = 42;");
}
fn compile(source: string): ComponentCompileReport {
    const manifests: ComponentManifests = {
        entries: list<ComponentSlotManifest>()
    };
    return compile_report(source, "sample.weiv", &manifests);
}
fn complete(source: string): ComponentUnit {
    var report = compile(source);
    return take_unit(&report) catch (code) {
        panic("Expected complete unit");
    };
}
fn expect_incomplete(report: &ComponentCompileReport): void {
    const unit = take_unit(report) catch (code) {
        assert(code == TakeUnitError.incomplete_report);
        assert(not report.consumed);
        return;
    };
    panic("Incomplete report cannot produce a unit");
}

fn failure(
    source: string,
    stage: CompilationStage,
    expected: string,
    diagnostic_code: string
): ComponentCompileReport {
    var report = compile(source);
    if report.failure is problem {
        assert(problem.stage == stage);
        assert(problem.code == expected);
    } else {
        assert(false);
    }
    assert(report.diagnostics.len() > 0);
    if report.diagnostics.len() > 0 {
        const last = &report.diagnostics[report.diagnostics.len() - 1];
        assert(last.fatal);
        assert(last.code == diagnostic_code);
    }
    expect_incomplete(&report);
    return report;
}

test "coordinator owns complete source and outputs beyond caller and report lifetimes" {
    const unit = complete(valid_input("<p id=\"a\">{{value}}</p>"));
    assert(unit.source_path == "sample.weiv");
    assert(unit.script.facts.ok);
    assert(unit.script.transpiled_code.bytes().len() > 0);
    assert(unit.template_document.nodes.len() == 2);
    assert(unit.normalized_template.nodes.len() == 2);
    assert(unit.lir_document.nodes.len() == 2);
    assert(unit.lir_document.expressions[0].references[0].name == "value");
    const bytes = unit.source.bytes();
    const template = bytes[unit.sfc_document.template.content_span.start..unit.sfc_document.template.content_span.end];
    const payload = &unit.lir_document.nodes[unit.lir_document.roots[0]].payload;
    switch payload {
        .element(element) => {
            assert(text(template, element.tag_name) == "p");
        }
        _ => {
            assert(false);
        }
    }
    if unit.sfc_document.style is style {
        assert(text(bytes, style.content_span) == "p { color: red }");
    } else {
        assert(false);
    }
}

test "unit transfer detaches owning stages once and retains diagnostic context" {
    var report = compile(valid_input("{{missing}}"));
    const count = report.diagnostics.len();
    assert(count > 0);
    const unit = take_unit(&report) catch (code) {
        panic("Expected complete unit");
    };
    assert(report.consumed);
    assert(report.diagnostics.len() == count);
    assert(report.source == unit.source);
    if report.sfc_document is value {} else {
        assert(false);
    }
    if report.template_document is value {
        assert(false);
    }
    if report.normalized_template is value {
        assert(false);
    }
    if report.script is value {
        assert(false);
    }
    if report.template_bindings is value {
        assert(false);
    }
    if report.lir_document is value {
        assert(false);
    }
    const diagnostic = &report.diagnostics[0];
    if map_span(&report, diagnostic) is mapped {} else {
        assert(false);
    }
    const second = take_unit(&report) catch (code) {
        assert(code == TakeUnitError.consumed_report);
        return;
    };
    assert(false);
}

test "SFC failure retains source but no later stages" {
    const report = failure("", CompilationStage.sfc_parse, "sfc.missing_template", "sfc.missing_template");
    assert(report.source == "");
    if report.sfc_document is value {
        assert(false);
    }
    if report.script is value {
        assert(false);
    }
}

test "template failure retains SFC and skips script backend" {
    const report = failure(
        valid_input("<p>"),
        CompilationStage.template_parse,
        "template.mismatched_close_tag",
        "template.mismatched_close_tag"
    );
    if report.sfc_document is value {} else {
        assert(false);
    }
    if report.template_document is value {
        assert(false);
    }
    if report.script is value {
        assert(false);
    }
}

test "normalization failure retains raw template and skips script backend" {
    const report = failure(
        valid_input("<p #else/>"),
        CompilationStage.template_normalize,
        "template.unexpected_else",
        "template.unexpected_else"
    );
    if report.template_document is raw {
        assert(raw.nodes.len() == 1);
    } else {
        assert(false);
    }
    if report.normalized_template is value {
        assert(false);
    }
    if report.script is value {
        assert(false);
    }
}

test "backend transport failure is distinct from script rejection" {
    const manifests: ComponentManifests = {
        entries: list<ComponentSlotManifest>()
    };
    const path: [3]u8 = [97, 0, 98];
    const report = compile_report(valid_input("<p/>"), string.from(path[..3]), &manifests);
    if report.failure is value {
        assert(value.stage == CompilationStage.script_backend);
        assert(value.code == "embedded_nul");
    } else {
        assert(false);
    }
    if report.normalized_template is value {} else {
        assert(false);
    }
    if report.script is value {
        assert(false);
    }
}

test "invalid script retains decoded diagnostics and stops before binding" {
    const report = failure(
        input("<p/>", "export const broken = ;"),
        CompilationStage.script_facts,
        "invalid_script",
        "script.syntax"
    );
    if report.script is script {
        assert(not script.facts.ok);
    } else {
        assert(false);
    }
    if report.template_bindings is value {
        assert(false);
    }
    var found = false;
    var i: usize = 0;
    while i < report.diagnostics.len() {
        const diagnostic = &report.diagnostics[i];
        if diagnostic.origin == SourceOrigin.script {
            assert(diagnostic.stage == CompilationStage.script_facts);
            assert(diagnostic.fatal);
            found = true;
        }
        i = i + 1;
    }
    assert(found);
}

test "binding diagnostics remain nonfatal and retain template coordinates" {
    const report = compile(valid_input("{{missing}}"));
    if report.failure is value {
        assert(false);
    }
    if report.lir_document is value {} else {
        assert(false);
    }
    var found = false;
    var i: usize = 0;
    while i < report.diagnostics.len() {
        const diagnostic = &report.diagnostics[i];
        if diagnostic.stage == CompilationStage.binding {
            assert(not diagnostic.fatal);
            assert(diagnostic.origin == SourceOrigin.template);
            if map_span(&report, diagnostic) is mapped {
                if report.sfc_document is sfc {
                    if diagnostic.span is local {
                        assert(mapped.start == sfc.template.content_span.start + local.start);
                    }
                }
            } else {
                assert(false);
            }
            found = true;
        }
        i = i + 1;
    }
    assert(found);
}

test "lowering failure retains all preceding stages and exact error" {
    const report = failure(
        valid_input("<p slot:head/>"),
        CompilationStage.lowering,
        "template.invalid_slot_placement",
        "template.invalid_slot_placement"
    );
    if report.template_bindings is value {} else {
        assert(false);
    }
    if report.script is value {} else {
        assert(false);
    }
    if report.lir_document is value {
        assert(false);
    }
}

test "immutable supplied manifests are used without filesystem resolution" {
    var slots = list<SlotEntry>();
    slots.push(SlotEntry {
        name: "head",
        span: {
            start: 0,
            end: 0
        }
    });
    var manifests: ComponentManifests = {
        entries: list<ComponentSlotManifest>()
    };
    manifests.entries.push(ComponentSlotManifest {
        tag_name: "Card",
        manifest: SlotManifest {
            entries: slots
        }
    });
    const source = input("<Card><p slot:head/></Card>", "export interface Props {} export let props: Props; export const Card = {};");
    const report = compile_report(source, "no-file.weiv", &manifests);
    if report.failure is value {
        assert(false);
    }
    if report.template_bindings is bindings {
        assert(bindings.component_refs[0].resolved);
    } else {
        assert(false);
    }
    assert(manifests.entries.len() == 1);
    const entry = &manifests.entries[0];
    assert(entry.manifest.entries.len() == 1);
}

fn diagnostic(origin: SourceOrigin, start: usize, end: usize): CompilationDiagnostic {
    return {
        stage: CompilationStage.binding,
        origin: origin,
        severity: "warning",
        code: "test",
        message: "test",
        span: Span {
            start: start,
            end: end
        },
        fatal: false
    };
}

test "source mapping distinguishes file template script and rejects invalid ranges" {
    const report = compile(valid_input("<p/>"));
    const template = diagnostic(SourceOrigin.template, 0, 4);
    const script = diagnostic(SourceOrigin.script, 0, 6);
    const file = diagnostic(SourceOrigin.file, 0, 10);
    if map_span(&report, &template) is span {
        assert(text(report.source.bytes(), span) == "<p/>");
    } else {
        assert(false);
    }
    if map_span(&report, &script) is span {
        assert(text(report.source.bytes(), span) == "export");
    } else {
        assert(false);
    }
    if map_span(&report, &file) is span {
        assert(text(report.source.bytes(), span) == "<template>");
    } else {
        assert(false);
    }
    const inverted = diagnostic(SourceOrigin.template, 3, 1);
    const outside = diagnostic(SourceOrigin.template, 0, 10000);
    if map_span(&report, &inverted) is span {
        assert(false);
    }
    if map_span(&report, &outside) is span {
        assert(false);
    }
    const incomplete = compile("bad");
    if map_span(&incomplete, &template) is span {
        assert(false);
    }
    const retained = diagnostic(SourceOrigin.file, 0, 0);
    if map_span(&incomplete, &retained) is span {
        assert(span.start == 0);
        assert(span.end == 0);
    } else {
        assert(false);
    }
}
