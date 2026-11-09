// Operation: script/module lowering failure -> structured Weiv diagnostic.
import { ProjectDiagnostic, DiagnosticLocation, location } from .compiler.project.diagnostics;
import { BrowserComponent } from .compiler.backend.browser.component;
import { CellSelection } from .compiler.backend.browser.emit.cell_selection;
import { select as select_names } from .compiler.backend.browser.emit.js_module.select_cells;
import { collect as collect_template_functions } from .compiler.lower.collect_template_functions;
import { append as append_template_function } from .compiler.lower.build_template_functions;
import { cell_script_diagnostics_raw, lower_cells_raw, analyze_module_state_raw, expression_supported, handler_supported } from .ffi.script_backend;
import { Span } from .compiler.source;
import std.json;
import std.mem;
import { Value } from std.json;
import { ScriptDecodeError } from .compiler.sema.script_json;
import .compiler.sema.script_json as validation;

struct CellDiagnosticRecord {
    reason: string;
    span: Span;
    message: ?string;
}

fn decode_record(value: &const Value): CellDiagnosticRecord ! ScriptDecodeError {
    return switch value {
        .object(object) => CellDiagnosticRecord {
            reason: try validation.text_field(&object, "reason"),
            span: try validation.span(&object, "span_start", "span_end"),
            message: try validation.optional_text_field(&object, "message")
        };
        _ => {
            throw ScriptDecodeError.wrong_type;
        }
    };
}

struct Detail {
    code: string;
    message: string;
}

fn error_name(reason: string): string {
    if reason == "assignment_pattern" {
        return "CellAssignmentPatternUnsupported";
    }
    if reason == "declaration_kind" {
        return "CellVarDeclarationUnsupported";
    }
    if reason == "template_mutation" {
        return "CellTemplateMutationUnsupported";
    }
    if reason == "dynamic_eval" {
        return "CellDynamicEvalUnsupported";
    }
    if reason == "top_level_await" {
        return "CellTopLevelAwaitUnsupported";
    }
    if reason == "ambient_declaration" {
        return "CellAmbientDeclarationUnsupported";
    }
    if reason == "const_assignment" {
        return "CellConstAssignmentUnsupported";
    }
    if reason == "reserved_identifier" {
        return "CellReservedIdentifier";
    }
    if reason == "template_untracked_assignment" {
        return "CellTemplateUntrackedAssignmentUnsupported";
    }
    if reason == "component_default_export" {
        return "CellComponentDefaultExportUnsupported";
    }
    if reason == "dynamic_module_import" {
        return "OpaqueDynamicModuleImportUnsupported";
    }
    if reason == "component_dynamic_module_import" {
        return "OpaqueDynamicModuleImportUnsupported";
    }
    return "CellDeclarationUnsupported";
}

fn details(reason: string): Detail {
    if reason == "assignment_pattern" {
        return {
            code: "reactivity.unsupported_expression",
            message: "This expression cannot be lowered with reactive state. Simplify it into a statically defined script helper or use an explicit subscription adapter."
        };
    }
    if reason == "declaration_kind" {
        return {
            code: "reactivity.unsupported_declaration",
            message: "Compiler-managed state requires let or const declarations. Replace this var declaration with a lexical declaration and check its initialization order."
        };
    }
    if reason == "template_mutation" {
        return {
            code: "reactivity.render_mutation",
            message: "Render expressions cannot mutate state immediately. Move this write into an event handler or deferred callback."
        };
    }
    if reason == "dynamic_eval" {
        return {
            code: "reactivity.dynamic_eval",
            message: "Dynamic eval cannot preserve compiler-managed reactive bindings. Use a statically defined function or an explicit subscription adapter."
        };
    }
    if reason == "top_level_await" {
        return {
            code: "reactivity.unsupported_await",
            message: "Synchronous state setup and binding-pattern extraction cannot await here. Move asynchronous work into an async helper; managed modules may await their pattern's input before extraction."
        };
    }
    if reason == "ambient_declaration" {
        return {
            code: "reactivity.ambient_declaration",
            message: "An ambient declaration has no runtime storage for managed state. Provide a real initializer or import state with an explicit observable or subscription contract."
        };
    }
    if reason == "const_assignment" {
        return {
            code: "reactivity.readonly_assignment",
            message: "This expression writes a readonly binding. Use let for replaceable local state, a managed module's exported mutation function for imports, or update an item's supported data members instead of replacing a loop alias."
        };
    }
    if reason == "reserved_identifier" {
        return {
            code: "reactivity.reserved_identifier",
            message: "Names beginning with __weiv_ are reserved for compiler internals. Rename this binding."
        };
    }
    if reason == "template_untracked_assignment" {
        return {
            code: "reactivity.untracked_assignment",
            message: "This expression replaces a binding that is not managed reactive state. Use a let binding for replaceable callable state; update props through their owner."
        };
    }
    if reason == "component_default_export" {
        return {
            code: "reactivity.component_default_export",
            message: "Component setup cannot contain a default export. Remove this export and use the component's template and props interface; shared modules may retain native default exports."
        };
    }
    if reason == "dynamic_module_import" {
        return {
            code: "reactivity.dynamic_module_import",
            message: "Managed builds cannot resolve the target of this computed import. Use a literal module specifier or load outside the managed boundary and transfer updates through an observable/subscription adapter."
        };
    }
    if reason == "component_dynamic_module_import" {
        return {
            code: "reactivity.dynamic_module_import",
            message: "Component/template dynamic imports are outside experimental managed loading. Put a literal import() loader in a managed JS/TS module, or use an external observable/subscription adapter."
        };
    }
    return {
        code: "reactivity.unsupported_expression",
        message: "This expression cannot be lowered with reactive state. Simplify it into a statically defined script helper or use an explicit subscription adapter."
    };
}

fn dynamic_import_spans(source: string): List<Span> {
    var output = list<Span>();
    const bytes = source.bytes();
    var cursor: usize = 0;
    while cursor < bytes.len() {
        const found = mem.index_of(bytes[cursor..], "import(".bytes());
        if found is position {
            const start = cursor + position;
            var end = start + 7;
            var diagnostic_start = start;
            var depth: usize = 1;
            while end < bytes.len() and depth > 0 {
                if bytes[end] == 40 {
                    depth = depth + 1;
                } else if bytes[end] == 41 {
                    depth = depth - 1;
                }
                end = end + 1;
            }
            if end > start + 7 and (bytes[start + 7] == 39 or bytes[start + 7] == 34) {
                const quote = bytes[start + 7];
                var quoted_end = start + 8;
                while quoted_end < end and bytes[quoted_end] != quote {
                    quoted_end = quoted_end + 1;
                }
                if quoted_end < end {
                    diagnostic_start = start + 7;
                    end = quoted_end + 1;
                }
            }
            output.push(Span {
                start: diagnostic_start,
                end: end
            });
            cursor = end;
        } else {
            break;
        }
    }
    return output;
}

fn opaque_dynamic_import_count(source: string, source_path: string): usize {
    const raw = analyze_module_state_raw(source, source_path) catch (code) {
        return 0;
    };
    const value = json.parse(raw) catch (code) {
        return 0;
    };
    switch value {
        .object(object) => {
            const sites = validation.record_field<Span>(&object, "opaque_dynamic_imports", decode_span) catch (code) {
                return 0;
            };
            return sites.len();
        }
        _ => {
            return 0;
        }
    }
}

fn decode_span(value: &const Value): Span ! ScriptDecodeError {
    return switch value {
        .object(object) => try validation.span(&object, "span_start", "span_end");
        _ => {
            throw ScriptDecodeError.wrong_type;
        }
    };
}

fn append_dynamic_imports(output: &List<ProjectDiagnostic>, source: string, source_path: string, document_path: string, document: string, offset: usize, all_imports: bool): void {
    const spans = dynamic_import_spans(source);
    var count = spans.len();
    if not all_imports {
        const opaque = opaque_dynamic_import_count(source, source_path);
        count = opaque;
    }
    var i: usize = 0;
    while i < count and i < spans.len() {
        const relative = spans[i];
        const absolute = Span {
            start: offset + relative.start,
            end: offset + relative.end
        };
        var reason = "dynamic_module_import";
        if all_imports {
            reason = "component_dynamic_module_import";
        }
        append_failure(output, source_path, document_path, document, absolute, reason);
        i = i + 1;
    }
}

pub fn inspect_module(source: string, source_path: string, document_path: string, document: string, names: string, include_cells: bool): List<ProjectDiagnostic> {
    var output = list<ProjectDiagnostic>();
    append_dynamic_imports(&output, source, source_path, document_path, document, 0, false);
    if output.len() > 0 or not include_cells {
        return output;
    }
    return inspect(source, source_path, document_path, document, 0, names, true);
}

fn append_failure(output: &List<ProjectDiagnostic>, source_path: string, document_path: string, document: string, span: Span, reason: string): void {
    const detail = details(reason);
    var message = detail.message;
    if reason != "component_dynamic_module_import" {
        const failure_name = error_name(reason);
        message = $"{detail.message} ({failure_name})";
    }
    output.push(ProjectDiagnostic {
        code: string.from(detail.code.bytes()),
        severity: "error",
        stage: "emit",
        message: message,
        source_path: document_path,
        span: span,
        location: location(document, span.start),
        fatal: true
    });
}

pub fn inspect(source: string, source_path: string, document_path: string, document: string, offset: usize, names: string, is_module: bool): List<ProjectDiagnostic> {
    var output = list<ProjectDiagnostic>();
    append_dynamic_imports(&output, source, source_path, document_path, document, offset, not is_module);
    if output.len() > 0 {
        return output;
    }
    const raw = cell_script_diagnostics_raw(source, source_path, names, is_module) catch (code) {
        return output;
    };
    const value = json.parse(raw) catch (code) {
        return output;
    };
    switch value {
        .array(array) => {
            var i: usize = 0;
            while i < array.items.len() {
                const record = decode_record(&array.items[i]) catch (code) {
                    i = i + 1;
                    continue;
                };
                if record.span.start > record.span.end or record.span.end > source.bytes().len() {
                    i = i + 1;
                    continue;
                }
                const absolute = Span {
                    start: offset + record.span.start,
                    end: offset + record.span.end
                };
                var code = "script.syntax";
                var message = "Invalid script syntax";
                if record.message is detail {
                    message = $"{detail}. Correct this script/module syntax before reactive lowering.";
                    output.push(ProjectDiagnostic {
                        code: string.from(code.bytes()),
                        severity: "error",
                        stage: "emit",
                        message: message,
                        source_path: document_path,
                        span: absolute,
                        location: location(document, absolute.start),
                        fatal: true
                    });
                } else {
                    append_failure(&output, source_path, document_path, document, absolute, record.reason);
                }
                i = i + 1;
            }
        }
        _ => {
            return output;
        }
    }
    return output;
}

struct LowerFailure {
    reason: string;
}

fn decode_lower_failure(value: &const Value): ?LowerFailure ! ScriptDecodeError {
    switch value {
        .object(object) => {
            const failure = try validation.optional_text_field(&object, "error");
            if failure is reason {
                return LowerFailure {
                    reason: reason
                };
            }
            return none;
        }
        _ => {
            throw ScriptDecodeError.wrong_type;
        }
    }
}

pub fn inspect_component(component: &const BrowserComponent, selection: &const CellSelection, document_path: string): List<ProjectDiagnostic> {
    const unit = &component.unit;
    const script_span = unit.sfc_document.script.content_span;
    const script = string.from(unit.source.bytes()[script_span.start..script_span.end]);
    const names = select_names(unit, selection) catch (code) {
        return list<ProjectDiagnostic>();
    };
    var output = inspect(script, unit.source_path, document_path, unit.source, script_span.start, names, false);
    if output.len() > 0 {
        return output;
    }
    const template_span = unit.sfc_document.template.content_span;
    const template = string.from(unit.source.bytes()[template_span.start..template_span.end]);
    const inputs = collect_template_functions(template.bytes(), &unit.template_document, &unit.normalized_template, &unit.script.facts);
    const template_offset = template_span.start;
    var input_index: usize = 0;
    while input_index < inputs.expressions.len() {
        const input = &inputs.expressions[input_index];
        const expression = string.from(template.bytes()[input.expression.start..input.expression.end]);
        if mem.index_of(expression.bytes(), "import(".bytes()) is found {
            const import_spans = dynamic_import_spans(expression);
            const import_span = &import_spans[0];
            const absolute = Span {
                start: template_offset + input.expression.start + import_span.start,
                end: template_offset + input.expression.start + import_span.end
            };
            append_failure(&output, unit.source_path, document_path, unit.source, absolute, "component_dynamic_module_import");
            input_index = input_index + 1;
            continue;
        }
        var supported = false;
        if input.argument is none {
            supported = expression_supported(expression) catch (code) => false;
        } else {
            supported = handler_supported(expression) catch (code) => false;
        }
        if not supported {
            const absolute = Span {
                start: template_offset + input.expression.start,
                end: template_offset + input.expression.end
            };
            var reason = "template_mutation";
            if mem.index_of(expression.bytes(), "eval".bytes()) is found {
                reason = "dynamic_eval";
            } else if mem.index_of(expression.bytes(), "import(".bytes()) is found {
                reason = "dynamic_module_import";
            }
            append_failure(&output, unit.source_path, document_path, unit.source, absolute, reason);
            input_index = input_index + 1;
            continue;
        }
        var generated = list<u8>();
        const _ = append_template_function(&generated, expression, &input.locals, &inputs.script_names, input.argument) catch (code) {
            input_index = input_index + 1;
            continue;
        };
        const response = lower_cells_raw(script, unit.source_path, names, string.from(generated.view())) catch (code) {
            input_index = input_index + 1;
            continue;
        };
        const parsed = json.parse(response) catch (code) {
            input_index = input_index + 1;
            continue;
        };
        const failure = decode_lower_failure(&parsed) catch (code) {
            input_index = input_index + 1;
            continue;
        };
        if failure is value {
            const absolute = Span {
                start: template_offset + input.expression.start,
                end: template_offset + input.expression.end
            };
            append_failure(&output, unit.source_path, document_path, unit.source, absolute, value.reason);
        }
        input_index = input_index + 1;
    }
    return output;
}
