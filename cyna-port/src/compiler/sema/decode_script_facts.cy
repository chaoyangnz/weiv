// Operation: backend JSON -> owned script facts and separate code; validates fields.
import { DecodedScript } from .compiler.sema.decoded_script;
import { Value } from std.json;
import std.json;
import { ScriptDecodeError } from .compiler.sema.script_json;
import .compiler.sema.script_json as validation;
import { ScriptFacts, PropsFacts, StateFacts, ScriptImport, ScriptBinding, ScriptDiagnostic, HelperFacts, MutationFacts, AliasFacts, CallbackRegistrationFacts } from .compiler.sema.script_facts;

fn decode_text(value: &const Value): string ! ScriptDecodeError {
    return try validation.text(value);
}

fn decode_import(value: &const Value): ScriptImport ! ScriptDecodeError {
    return switch value {
        .object(object) => ScriptImport {
            source: try validation.text_field(&object, "source"),
            kind: try validation.text_field(&object, "kind"),
            imported_name: try validation.optional_text_field(&object, "imported_name"),
            local_name: try validation.text_field(&object, "local_name"),
            span: try validation.span(&object, "span_start", "span_end"),
        };
        _ => {
            throw ScriptDecodeError.wrong_type;
        }
    };
}

fn decode_binding(value: &const Value): ScriptBinding ! ScriptDecodeError {
    return switch value {
        .object(object) => ScriptBinding {
            name: try validation.text_field(&object, "name"),
            kind: try validation.text_field(&object, "kind"),
            exported: try validation.bool_field(&object, "exported"),
            template_visible: try validation.bool_field(&object, "template_visible"),
            callable: try validation.bool_field(&object, "callable"),
            type_annotation: try validation.optional_text_field(&object, "type_annotation"),
            span: try validation.span(&object, "span_start", "span_end"),
        };
        _ => {
            throw ScriptDecodeError.wrong_type;
        }
    };
}

fn decode_diagnostic(value: &const Value): ScriptDiagnostic ! ScriptDecodeError {
    return switch value {
        .object(object) => ScriptDiagnostic {
            severity: try validation.text_field(&object, "severity"),
            message: try validation.text_field(&object, "message"),
            span: try validation.span(&object, "span_start", "span_end"),
            line: (try validation.unsigned(try validation.required(&object, "line"), 4294967295)) as u32,
            column: (try validation.unsigned(try validation.required(&object, "column"), 4294967295)) as u32,
            code: try validation.optional_text_field(&object, "code"),
        };
        _ => {
            throw ScriptDecodeError.wrong_type;
        }
    };
}

fn decode_helper(value: &const Value): HelperFacts ! ScriptDecodeError {
    return switch value {
        .object(object) => HelperFacts {
            name: try validation.text_field(&object, "name"),
            kind: try validation.text_field(&object, "kind"),
            span: try validation.span(&object, "span_start", "span_end"),
            reads: try validation.record_field<string>(&object, "reads", decode_text),
            writes: try validation.record_field<string>(&object, "writes", decode_text),
            calls: try validation.record_field<string>(&object, "calls", decode_text),
            async_flag: try validation.bool_field(&object, "async_flag"),
            returns_expression_only: try validation.bool_field(&object, "returns_expression_only"),
            contains_external_reads: try validation.bool_field(&object, "contains_external_reads"),
            contains_side_effects: try validation.bool_field(&object, "contains_side_effects"),
        };
        _ => {
            throw ScriptDecodeError.wrong_type;
        }
    };
}

fn decode_mutation(value: &const Value): MutationFacts ! ScriptDecodeError {
    return switch value {
        .object(object) => MutationFacts {
            binding: try validation.text_field(&object, "binding"),
            kind: try validation.text_field(&object, "kind"),
            span: try validation.span(&object, "span_start", "span_end"),
            statement_position: try validation.bool_field(&object, "statement_position"),
            member_path: try validation.optional_text_field(&object, "member_path"),
            inside_callback: try validation.bool_field(&object, "inside_callback"),
            callback_owned_candidate: try validation.bool_field(&object, "callback_owned_candidate"),
        };
        _ => {
            throw ScriptDecodeError.wrong_type;
        }
    };
}

fn decode_alias(value: &const Value): AliasFacts ! ScriptDecodeError {
    return switch value {
        .object(object) => AliasFacts {
            alias: try validation.text_field(&object, "alias"),
            target: try validation.text_field(&object, "target"),
            kind: try validation.text_field(&object, "kind"),
            span: try validation.span(&object, "span_start", "span_end"),
        };
        _ => {
            throw ScriptDecodeError.wrong_type;
        }
    };
}

fn decode_callback(value: &const Value): CallbackRegistrationFacts ! ScriptDecodeError {
    return switch value {
        .object(object) => CallbackRegistrationFacts {
            callee: try validation.text_field(&object, "callee"),
            callback_kind: try validation.text_field(&object, "callback_kind"),
            span: try validation.span(&object, "callback_span_start", "callback_span_end"),
            owned_candidate: try validation.bool_field(&object, "owned_candidate"),
            reason: try validation.text_field(&object, "reason"),
        };
        _ => {
            throw ScriptDecodeError.wrong_type;
        }
    };
}

fn decode_props(value: &const Value): ?PropsFacts ! ScriptDecodeError {
    switch value {
        .null_value => {
            const empty: ?PropsFacts = none;
            return empty;
        }
        .object(object) => {
            const props: PropsFacts = {
                has_props_export: try validation.bool_field(&object, "has_props_export"),
                props_binding_name: try validation.optional_text_field(&object, "props_binding_name"),
                props_type_name: try validation.optional_text_field(&object, "props_type_name")
            };
            const present: ?PropsFacts = props;
            return present;
        }
        _ => {
            throw ScriptDecodeError.wrong_type;
        }
    }
}

fn empty_state(): StateFacts {
    return {
        helpers: list<HelperFacts>(),
        mutations: list<MutationFacts>(),
        aliases: list<AliasFacts>(),
        callback_registrations: list<CallbackRegistrationFacts>()
    };
}

fn decode_state(value: &const Value): StateFacts ! ScriptDecodeError {
    return switch value {
        .null_value => empty_state();
        .object(object) => StateFacts {
            helpers: try validation.default_records<HelperFacts>(&object, "helpers", decode_helper),
            mutations: try validation.default_records<MutationFacts>(&object, "mutations", decode_mutation),
            aliases: try validation.default_records<AliasFacts>(&object, "aliases", decode_alias),
            callback_registrations: try validation.default_records<CallbackRegistrationFacts>(&object, "callback_registrations", decode_callback)
        };
        _ => {
            throw ScriptDecodeError.wrong_type;
        }
    };
}

pub fn decode(source: string): DecodedScript ! ScriptDecodeError {
    const root = json.parse(source) catch (code) {
        throw ScriptDecodeError.invalid_json;
    };
    switch root {
        .object(object) => {
            const facts: ScriptFacts = {
                ok: try validation.bool_field(&object, "ok"),
                source_path: try validation.text_field(&object, "source_path"),
                props: try decode_props(try validation.required(&object, "props")),
                imports: try validation.record_field<ScriptImport>(&object, "imports", decode_import),
                bindings: try validation.record_field<ScriptBinding>(&object, "bindings", decode_binding),
                state_facts: try decode_state(try validation.required(&object, "state_analysis")),
                diagnostics: try validation.record_field<ScriptDiagnostic>(&object, "diagnostics", decode_diagnostic)
            };
            return {
                facts: facts,
                transpiled_code: try validation.text_field(&object, "transpiled_code")
            };
        }
        _ => {
            throw ScriptDecodeError.wrong_type;
        }
    }
}
