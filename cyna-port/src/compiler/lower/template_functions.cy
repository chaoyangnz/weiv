// Model: lexical function inputs and generated-to-template expression mappings.
import { Span } from .compiler.source;

pub struct TemplateFunctionInput {
    pub expression: Span;
    pub locals: List<string>;
    pub argument: ?string;
}
pub struct TemplateFunctionInputs {
    pub script_names: List<string>;
    pub expressions: List<TemplateFunctionInput>;
}
pub struct TemplateFunctionRecord {
    pub generated: Span;
    pub template: Span;
}
pub struct TemplateFunctions {
    // Caller-supplied prefix followed by comma-separated evaluator functions; no array suffix.
    pub code: string;
    pub records: List<TemplateFunctionRecord>;
}
