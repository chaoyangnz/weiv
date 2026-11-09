// Boundary operation: retained Rust lowering response -> owned code or typed emission failure.
import std.json;
import .compiler.sema.script_json as validation;
import { JavaScriptError } from .compiler.backend.browser.emit.javascript_errors;

pub fn decode(payload: string): string ! JavaScriptError {
    const value = json.parse(payload) catch (code) {
        throw JavaScriptError.invalid_backend_response;
    };
    switch value {
        .object(object) => {
            const code = validation.text_field(&object, "code") catch (error) {
                throw JavaScriptError.invalid_backend_response;
            };
            const failure = validation.optional_text_field(&object, "error") catch (error) {
                throw JavaScriptError.invalid_backend_response;
            };
            if failure is reason {
                if reason == "assignment_pattern" {
                    throw JavaScriptError.cell_assignment_pattern_unsupported;
                }
                if reason == "declaration_kind" {
                    throw JavaScriptError.cell_var_declaration_unsupported;
                }
                if reason == "dynamic_eval" {
                    throw JavaScriptError.cell_dynamic_eval_unsupported;
                }
                if reason == "top_level_await" {
                    throw JavaScriptError.cell_top_level_await_unsupported;
                }
                if reason == "ambient_declaration" {
                    throw JavaScriptError.cell_ambient_declaration_unsupported;
                }
                if reason == "const_assignment" {
                    throw JavaScriptError.cell_const_assignment_unsupported;
                }
                if reason == "reserved_identifier" {
                    throw JavaScriptError.cell_reserved_identifier;
                }
                if reason == "template_untracked_assignment" {
                    throw JavaScriptError.cell_template_untracked_assignment_unsupported;
                }
                if reason == "component_default_export" {
                    throw JavaScriptError.cell_component_default_export_unsupported;
                }
                throw JavaScriptError.cell_declaration_unsupported;
            }
            return code;
        }
        _ => {
            throw JavaScriptError.invalid_backend_response;
        }
    }
}
