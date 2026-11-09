// Model: complete compilation unit and inspectable partial report; owns source.
import { SfcDocument } from .compiler.parser.sfc.ast;
import { TemplateDocument } from .compiler.parser.template.ast;
import { NormalizedDocument } from .compiler.parser.template.normalized;
import { DecodedScript } from .compiler.sema.decoded_script;
import { TemplateBindings } from .compiler.sema.template_bindings;
import { LirDocument } from .compiler.lower.lir;
import { CompilationDiagnostic, CompilationFailure } from .compiler.diagnostics;

pub struct ComponentUnit {
    pub source: string;
    pub source_path: string;
    pub sfc_document: SfcDocument;
    pub template_document: TemplateDocument;
    pub normalized_template: NormalizedDocument;
    pub script: DecodedScript;
    pub template_bindings: TemplateBindings;
    pub lir_document: LirDocument;
}

pub struct ComponentCompileReport {
    pub source: string;
    pub source_path: string;
    pub sfc_document: ?SfcDocument;
    pub template_document: ?TemplateDocument;
    pub normalized_template: ?NormalizedDocument;
    pub script: ?DecodedScript;
    pub template_bindings: ?TemplateBindings;
    pub lir_document: ?LirDocument;
    pub diagnostics: List<CompilationDiagnostic>;
    pub failure: ?CompilationFailure;
    pub consumed: bool;
}
