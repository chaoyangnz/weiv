// Model: semantic script facts; independent of JSON, transport and emitted JavaScript.
import { Span } from .compiler.source;

pub struct PropsFacts {
    pub has_props_export: bool;
    pub props_binding_name: ?string;
    pub props_type_name: ?string;
}

pub struct ScriptImport {
    pub source: string;
    pub kind: string;
    pub imported_name: ?string;
    pub local_name: string;
    pub span: Span;
}

pub struct ScriptBinding {
    pub name: string;
    pub kind: string;
    pub exported: bool;
    pub template_visible: bool;
    pub callable: bool;
    pub type_annotation: ?string;
    pub span: Span;
}

pub struct ScriptDiagnostic {
    pub severity: string;
    pub message: string;
    pub span: Span;
    pub line: u32;
    pub column: u32;
    pub code: ?string;
}

pub struct HelperFacts {
    pub name: string;
    pub kind: string;
    pub span: Span;
    pub reads: List<string>;
    pub writes: List<string>;
    pub calls: List<string>;
    pub async_flag: bool;
    pub returns_expression_only: bool;
    pub contains_external_reads: bool;
    pub contains_side_effects: bool;
}

pub struct MutationFacts {
    pub binding: string;
    pub kind: string;
    pub span: Span;
    pub statement_position: bool;
    pub member_path: ?string;
    pub inside_callback: bool;
    pub callback_owned_candidate: bool;
}

pub struct AliasFacts {
    pub alias: string;
    pub target: string;
    pub kind: string;
    pub span: Span;
}

pub struct CallbackRegistrationFacts {
    pub callee: string;
    pub callback_kind: string;
    pub span: Span;
    pub owned_candidate: bool;
    pub reason: string;
}

pub struct StateFacts {
    pub helpers: List<HelperFacts>;
    pub mutations: List<MutationFacts>;
    pub aliases: List<AliasFacts>;
    pub callback_registrations: List<CallbackRegistrationFacts>;
}

pub struct ScriptFacts {
    pub ok: bool;
    pub source_path: string;
    pub props: ?PropsFacts;
    pub imports: List<ScriptImport>;
    pub bindings: List<ScriptBinding>;
    pub state_facts: StateFacts;
    pub diagnostics: List<ScriptDiagnostic>;
}
