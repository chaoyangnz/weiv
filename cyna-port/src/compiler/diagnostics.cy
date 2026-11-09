// Model: compiler diagnostics retain their actual coordinate space.
import { Span } from .compiler.source;

pub enum CompilationStage {
    sfc_parse;
    template_parse;
    template_normalize;
    script_backend;
    script_decode;
    script_facts;
    binding;
    lowering;
    emit;
}
pub enum SourceOrigin {
    file;
    template;
    script;
}
pub struct CompilationDiagnostic {
    pub stage: CompilationStage;
    pub origin: SourceOrigin;
    pub severity: string;
    pub code: string;
    pub message: string;
    pub span: ?Span;
    pub fatal: bool;
}
pub struct CompilationFailure {
    pub stage: CompilationStage;
    pub code: string;
}
