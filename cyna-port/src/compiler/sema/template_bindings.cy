// Model: bound template references and diagnostics with explicit source-fragment origins.
import { Span } from .compiler.source;
import { SlotManifest } from .compiler.sema.slot_manifest;

pub struct ExpressionReference {
    pub name: string;
    pub call: bool;
}

pub struct ExpressionFacts {
    pub source: Span;
    pub references: List<ExpressionReference>;
}

pub struct ComponentRef {
    pub tag_name: string;
    pub resolved: bool;
    pub span: Span;
}

pub enum BindingSource {
    template;
    script;
}

pub struct TemplateBindingDiagnostic {
    pub origin: BindingSource;
    pub severity: string;
    pub kind: string;
    pub name: string;
    pub message: string;
    pub span: Span;
}

pub struct TemplateBindings {
    pub component_refs: List<ComponentRef>;
    pub expressions: List<ExpressionFacts>;
    pub diagnostics: List<TemplateBindingDiagnostic>;
    pub own_slot_manifest: SlotManifest;
}
