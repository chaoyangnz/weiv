// Pass-private lexical scope data and binding helpers; not a persistent IR model.
import std.mem;
import { Span } from .compiler.source;
import { ScriptFacts } from .compiler.sema.script_facts;
import { TemplateBindingDiagnostic, BindingSource } from .compiler.sema.template_bindings;

pub struct LoopScope {
    pub name: string;
    pub end: usize;
}

pub fn text(source: []const u8, span: Span): string {
    return string.from(source[span.start..span.end]);
}

pub fn visible(name: string, script: &const ScriptFacts, scopes: &const List<LoopScope>): bool {
    if name == "emit" {
        return true;
    }
    var i = scopes.len();
    while i > 0 {
        i = i - 1;
        const scope = &scopes[i];
        if scope.name == name {
            return true;
        }
    }
    i = 0;
    while i < script.bindings.len() {
        const binding = &script.bindings[i];
        if binding.template_visible and binding.name == name {
            return true;
        }
        i = i + 1;
    }
    return false;
}

fn append_diagnostic(output: &List<TemplateBindingDiagnostic>, kind: string, name: string, message: string, span: Span, origin: BindingSource): void {
    var severity = "info";
    if kind == "framework.reserved_binding" or kind == "unresolved_binding" or kind == "unresolved_component" {
        severity = "error";
    } else if mem.starts_with(kind.bytes(), "slot.".bytes()) {
        severity = "error";
    } else if kind == "helper.external_state" or kind == "helper.side_effects" or kind == "directive.deprecated_syntax" or kind == "directive.vue_structural_syntax" {
        severity = "warning";
    }
    output.push(TemplateBindingDiagnostic {
        origin: origin,
        severity: severity,
        kind: kind,
        name: name,
        message: message,
        span: span
    });
}

pub fn diagnostic(output: &List<TemplateBindingDiagnostic>, kind: string, name: string, message: string, span: Span): void {
    append_diagnostic(output, kind, name, message, span, BindingSource.template);
}

pub fn script_diagnostic(output: &List<TemplateBindingDiagnostic>, kind: string, name: string, message: string, span: Span): void {
    append_diagnostic(output, kind, name, message, span, BindingSource.script);
}
