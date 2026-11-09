// Coordinator operation: in-memory source + immutable imported manifests -> report.
import { LirDocument } from .compiler.lower.lir;
import { TemplateBindings } from .compiler.sema.template_bindings;
import { DecodedScript } from .compiler.sema.decoded_script;
import { NormalizedDocument } from .compiler.parser.template.normalized;
import { TemplateDocument } from .compiler.parser.template.ast;
import { SfcDocument } from .compiler.parser.sfc.ast;
import { ComponentUnit, ComponentCompileReport } from .compiler.component_unit;
import { CompilationDiagnostic, CompilationFailure, CompilationStage, SourceOrigin } from .compiler.diagnostics;
import { Span } from .compiler.source;
import { parse as parse_sfc, ParseError } from .compiler.parser.sfc.parse;
import { parse as parse_template } from .compiler.parser.template.parse;
import { TemplateParseError } from .compiler.parser.template.errors;
import { normalize, NormalizeError } from .compiler.parser.template.normalize;
import { analyze_raw, ScriptBackendError } from .ffi.script_backend;
import { decode } from .compiler.sema.decode_script_facts;
import { ScriptDecodeError } from .compiler.sema.script_json;
import { ComponentManifests } from .compiler.sema.component_manifests;
import { BindingSource } from .compiler.sema.template_bindings;
import { bind } from .compiler.sema.bind_template;
import { lower, LowerError } from .compiler.lower.lower_template;

pub enum TakeUnitError {
    incomplete_report;
    consumed_report;
}

fn fail(report: &ComponentCompileReport, stage: CompilationStage, code: string): void {
    report.failure = CompilationFailure {
        stage: stage,
        code: code
    };
}

fn halt(
    report: &ComponentCompileReport,
    stage: CompilationStage,
    code: string,
    message: string,
    span: ?Span,
    origin: SourceOrigin
): void {
    fail(report, stage, code);
    report.diagnostics.push(CompilationDiagnostic {
        stage: stage,
        origin: origin,
        severity: "error",
        code: code,
        message: message,
        span: span,
        fatal: true
    });
}

fn code_sfc_parse(error: ParseError): string {
    return switch error {
        ParseError.missing_template => "sfc.missing_template";
        ParseError.missing_script => "sfc.missing_script";
        ParseError.duplicate_template => "sfc.duplicate_template";
        ParseError.duplicate_script => "sfc.duplicate_script";
        ParseError.duplicate_style => "sfc.duplicate_style";
        ParseError.unknown_top_level_section => "sfc.unknown_top_level_section";
        ParseError.invalid_script_attributes => "sfc.invalid_script_attributes";
        ParseError.invalid_section_order => "sfc.invalid_section_order";
        ParseError.unterminated_open_tag => "sfc.unterminated_open_tag";
        ParseError.unterminated_close_tag => "sfc.unterminated_close_tag";
    };
}

fn message_sfc_parse(error: ParseError): string {
    return switch error {
        ParseError.missing_template => "Missing <template> section";
        ParseError.missing_script => "Missing <script lang=\"ts\"> section";
        ParseError.duplicate_template => "Duplicate <template> section";
        ParseError.duplicate_script => "Duplicate <script> section";
        ParseError.duplicate_style => "Duplicate <style> section";
        ParseError.unknown_top_level_section => "Unknown top-level section; only template, script, and style are supported";
        ParseError.invalid_script_attributes => "Only <script lang=\"ts\"> is supported";
        ParseError.invalid_section_order => "Sections must appear in template, script, style order";
        ParseError.unterminated_open_tag => "Unterminated top-level open tag";
        ParseError.unterminated_close_tag => "Unterminated top-level close tag";
    };
}

fn code_template_parse(error: TemplateParseError): string {
    return switch error {
        TemplateParseError.unexpected_close_tag => "template.unexpected_close_tag";
        TemplateParseError.unterminated_tag => "template.unterminated_tag";
        TemplateParseError.unterminated_interpolation => "template.unterminated_interpolation";
        TemplateParseError.mismatched_close_tag => "template.mismatched_close_tag";
        TemplateParseError.invalid_directive => "template.invalid_directive";
        TemplateParseError.invalid_slot_outlet => "template.invalid_slot_outlet";
    };
}

fn message_template_parse(error: TemplateParseError): string {
    return switch error {
        TemplateParseError.unexpected_close_tag => "Closing tag appeared without a matching open tag";
        TemplateParseError.unterminated_tag => "Unterminated template tag";
        TemplateParseError.unterminated_interpolation => "Unterminated interpolation";
        TemplateParseError.mismatched_close_tag => "Closing tag does not match the currently open element";
        TemplateParseError.invalid_directive => "Invalid template directive usage";
        TemplateParseError.invalid_slot_outlet => "<slot> only supports an optional name attribute and no directives";
    };
}

fn code_normalize(error: NormalizeError): string {
    return switch error {
        NormalizeError.unexpected_else => "unexpected_else";
    };
}

fn code_script_backend(error: ScriptBackendError): string {
    return switch error {
        ScriptBackendError.embedded_nul => "embedded_nul";
        ScriptBackendError.allocation_failure => "allocation_failure";
        ScriptBackendError.backend_failure => "backend_failure";
    };
}

fn code_script_decode(error: ScriptDecodeError): string {
    return switch error {
        ScriptDecodeError.invalid_json => "invalid_json";
        ScriptDecodeError.missing_field => "missing_field";
        ScriptDecodeError.wrong_type => "wrong_type";
        ScriptDecodeError.invalid_integer => "invalid_integer";
        ScriptDecodeError.integer_overflow => "integer_overflow";
        ScriptDecodeError.invalid_span => "invalid_span";
    };
}

fn code_lower(error: LowerError): string {
    return switch error {
        LowerError.invalid_slot_placement => "invalid_slot_placement";
        LowerError.invalid_slot_template_placement => "invalid_slot_template_placement";
    };
}

fn sfc_stage(report: &ComponentCompileReport): bool {
    const result = parse_sfc(report.source.bytes()) catch (code) {
        halt(report, CompilationStage.sfc_parse, code_sfc_parse(code), message_sfc_parse(code), none, SourceOrigin.file);
        return false;
    };
    report.sfc_document = result;
    return true;
}
fn template_stage(report: &ComponentCompileReport): bool {
    if report.sfc_document is sfc {
        const bytes = report.source.bytes();
        const result = parse_template(bytes[sfc.template.content_span.start..sfc.template.content_span.end]) catch (code) {
            const span = Span {
                start: 0,
                end: 1
            };
            halt(report, CompilationStage.template_parse, code_template_parse(code), message_template_parse(code), span, SourceOrigin.template);
            return false;
        };
        report.template_document = result;
        return true;
    }
    panic("Template parsing requires SFC");
}
fn normalize_stage(report: &ComponentCompileReport): bool {
    if report.template_document is raw {
        const result = normalize(&raw) catch (code) {
            const span = Span {
                start: 0,
                end: 1
            };
            halt(report, CompilationStage.template_normalize, "template.unexpected_else", "`else` must immediately follow a sibling element with `if`", span, SourceOrigin.template);
            return false;
        };
        report.normalized_template = result;
        return true;
    }
    panic("Normalization requires template");
}
fn script_stage(report: &ComponentCompileReport): bool {
    if report.sfc_document is sfc {
        const bytes = report.source.bytes();
        const script = string.from(bytes[sfc.script.content_span.start..sfc.script.content_span.end]);
        const payload = analyze_raw(script, report.source_path) catch (code) {
            halt(report, CompilationStage.script_backend, code_script_backend(code), code_script_backend(code), none, SourceOrigin.script);
            return false;
        };
        const result = decode(payload) catch (code) {
            halt(report, CompilationStage.script_decode, code_script_decode(code), code_script_decode(code), none, SourceOrigin.script);
            return false;
        };
        const valid = result.facts.ok;
        var i: usize = 0;
        while i < result.facts.diagnostics.len() {
            const diagnostic = &result.facts.diagnostics[i];
            var code = "script.analysis";
            if diagnostic.code is actual {
                code = actual;
            }
            report.diagnostics.push(CompilationDiagnostic {
                stage: CompilationStage.script_facts,
                origin: SourceOrigin.script,
                severity: diagnostic.severity,
                code: code,
                message: diagnostic.message,
                span: diagnostic.span,
                fatal: not valid
            });
            i = i + 1;
        }
        report.script = result;
        if not valid {
            fail(report, CompilationStage.script_facts, "invalid_script");
            return false;
        }
        return true;
    }
    panic("Script analysis requires SFC");
}
fn bind_stage(report: &ComponentCompileReport, manifests: &const ComponentManifests): void {
    if report.sfc_document is sfc {
        if report.template_document is raw {
            if report.normalized_template is normalized {
                if report.script is script {
                    const bytes = report.source.bytes();
                    const result = bind(bytes[sfc.template.content_span.start..sfc.template.content_span.end], &raw, &normalized, &script.facts, manifests);
                    var i: usize = 0;
                    while i < result.diagnostics.len() {
                        const diagnostic = &result.diagnostics[i];
                        const origin = switch diagnostic.origin {
                            BindingSource.template => SourceOrigin.template;
                            BindingSource.script => SourceOrigin.script;
                        };
                        report.diagnostics.push(CompilationDiagnostic {
                            stage: CompilationStage.binding,
                            origin: origin,
                            severity: diagnostic.severity,
                            code: diagnostic.kind,
                            message: diagnostic.message,
                            span: diagnostic.span,
                            fatal: false
                        });
                        i = i + 1;
                    }
                    report.template_bindings = result;
                    return;
                }
            }
        }
    }
    panic("Binding requires normalized template and script facts");
}
fn lower_stage(report: &ComponentCompileReport): void {
    if report.sfc_document is sfc {
        if report.template_document is raw {
            if report.normalized_template is normalized {
                if report.template_bindings is bindings {
                    const bytes = report.source.bytes();
                    const result = lower(bytes[sfc.template.content_span.start..sfc.template.content_span.end], &raw, &normalized, &bindings) catch (code) {
                        var lowering_code = "template.invalid_slot_placement";
                        var message = "`slot:name` may only be used on direct children of a component usage";
                        if code == LowerError.invalid_slot_template_placement {
                            lowering_code = "template.invalid_slot_template_placement";
                            message = "<template> grouping is only valid inside a component usage when paired with slot:name";
                        }
                        const span = Span {
                            start: 0,
                            end: 1
                        };
                        halt(report, CompilationStage.lowering, lowering_code, message, span, SourceOrigin.template);
                        return;
                    };
                    report.lir_document = result;
                    return;
                }
            }
        }
    }
    panic("Lowering requires bound template");
}

pub fn compile_report(source: string, source_path: string, manifests: &const ComponentManifests): ComponentCompileReport {
    var report: ComponentCompileReport = {
        source: source,
        source_path: source_path,
        sfc_document: none,
        template_document: none,
        normalized_template: none,
        script: none,
        template_bindings: none,
        lir_document: none,
        diagnostics: list<CompilationDiagnostic>(),
        failure: none,
        consumed: false
    };
    if not sfc_stage(&report) {
        return report;
    }
    if not template_stage(&report) {
        return report;
    }
    if not normalize_stage(&report) {
        return report;
    }
    if not script_stage(&report) {
        return report;
    }
    bind_stage(&report, manifests);
    lower_stage(&report);
    return report;
}

// Transfer detaches owning stages; source and SFC coordinate metadata remain for diagnostics.
pub fn take_unit(report: &ComponentCompileReport): ComponentUnit ! TakeUnitError {
    if report.consumed {
        throw TakeUnitError.consumed_report;
    }
    if report.failure is failure {
        throw TakeUnitError.incomplete_report;
    }
    if report.sfc_document is none {
        throw TakeUnitError.incomplete_report;
    }
    if report.template_document is none {
        throw TakeUnitError.incomplete_report;
    }
    if report.normalized_template is none {
        throw TakeUnitError.incomplete_report;
    }
    if report.script is none {
        throw TakeUnitError.incomplete_report;
    }
    if report.template_bindings is none {
        throw TakeUnitError.incomplete_report;
    }
    if report.lir_document is none {
        throw TakeUnitError.incomplete_report;
    }
    const sfc_document = report.sfc_document;
    const template_document = take report.template_document;
    const normalized_template = take report.normalized_template;
    const script = take report.script;
    const template_bindings = take report.template_bindings;
    const lir_document = take report.lir_document;
    report.consumed = true;
    return ComponentUnit {
        source: report.source,
        source_path: report.source_path,
        sfc_document: require_sfc_document(sfc_document),
        template_document: require_template_document(template_document),
        normalized_template: require_normalized_template(normalized_template),
        script: require_script(script),
        template_bindings: require_template_bindings(template_bindings),
        lir_document: require_lir_document(lir_document),
    };
}

fn require_sfc_document(value: ?SfcDocument): SfcDocument {
    if value is present {
        return present;
    }
    panic("Validated stage became absent");
}

fn require_template_document(value: ?TemplateDocument): TemplateDocument {
    if value is present {
        return present;
    }
    panic("Validated stage became absent");
}

fn require_normalized_template(value: ?NormalizedDocument): NormalizedDocument {
    if value is present {
        return present;
    }
    panic("Validated stage became absent");
}

fn require_script(value: ?DecodedScript): DecodedScript {
    if value is present {
        return present;
    }
    panic("Validated stage became absent");
}

fn require_template_bindings(value: ?TemplateBindings): TemplateBindings {
    if value is present {
        return present;
    }
    panic("Validated stage became absent");
}

fn require_lir_document(value: ?LirDocument): LirDocument {
    if value is present {
        return present;
    }
    panic("Validated stage became absent");
}
