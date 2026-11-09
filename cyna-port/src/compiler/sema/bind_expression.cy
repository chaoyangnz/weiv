// Operation: expression bytes + lexical/script facts -> references and binding diagnostics.
import { Span } from .compiler.source;
import { ScriptFacts } from .compiler.sema.script_facts;
import { ExpressionReference, ExpressionFacts, TemplateBindingDiagnostic } from .compiler.sema.template_bindings;
import { LoopScope } from .compiler.sema.binding_context;
import .compiler.sema.binding_context as context;

fn identifier_start(byte: u8): bool {
    return (byte >= 65 and byte <= 90) or (byte >= 97 and byte <= 122) or byte == 95 or byte == 36;
}

fn space(byte: u8): bool {
    return byte == 32 or byte == 9 or byte == 10 or byte == 13;
}

fn next_call(bytes: []const u8, start: usize): bool {
    var i = start;
    while i < bytes.len() and space(bytes[i]) {
        i = i + 1;
    }
    return i < bytes.len() and bytes[i] == 40;
}

fn property(bytes: []const u8, start: usize): bool {
    var i = start;
    while i > 0 {
        i = i - 1;
        if not space(bytes[i]) {
            if bytes[i] != 46 {
                return false;
            }
            return not (i >= 2 and bytes[i - 1] == 46 and bytes[i - 2] == 46);
        }
    }
    return false;
}

fn keyword(name: string): bool {
    return name == "true" or name == "false" or name == "null" or name == "undefined" or name == "in" or name == "typeof" or name == "return";
}

fn helper_warning(name: string, span: Span, script: &const ScriptFacts, diagnostics: &List<TemplateBindingDiagnostic>): void {
    var b: usize = 0;
    while b < script.bindings.len() {
        const binding = &script.bindings[b];
        if binding.template_visible and binding.callable and binding.name == name {
            var h: usize = 0;
            while h < script.state_facts.helpers.len() {
                const helper = &script.state_facts.helpers[h];
                if helper.name == name {
                    if helper.contains_external_reads {
                        context.diagnostic(diagnostics, "helper.external_state", name, "Local helper reads external state, so Weiv will treat this template call conservatively", span);
                    } else if helper.contains_side_effects {
                        context.diagnostic(diagnostics, "helper.side_effects", name, "Local helper has side effects, so Weiv will treat this template call conservatively", span);
                    }
                    return;
                }
                h = h + 1;
            }
            return;
        }
        b = b + 1;
    }
}

pub fn bind(source: []const u8, expression: Span, diagnostic_span: Span, script: &const ScriptFacts, scopes: &const List<LoopScope>, diagnostics: &List<TemplateBindingDiagnostic>): ExpressionFacts {
    const bytes = source[expression.start..expression.end];
    var references = list<ExpressionReference>();
    var seen = list<string>();
    var i: usize = 0;
    var quote: ?u8 = none;
    var template_depth: usize = 0;
    while i < bytes.len() {
        if quote is current {
            if bytes[i] == 92 and i + 1 < bytes.len() {
                i = i + 2;
            } else if current == 96 and bytes[i] == 36 and i + 1 < bytes.len() and bytes[i + 1] == 123 {
                template_depth = template_depth + 1;
                quote = none;
                i = i + 2;
            } else {
                if bytes[i] == current {
                    quote = none;
                }
                i = i + 1;
            }
        } else if template_depth > 0 and bytes[i] == 125 {
            template_depth = template_depth - 1;
            quote = 96;
            i = i + 1;
        } else if bytes[i] == 34 or bytes[i] == 39 or bytes[i] == 96 {
            quote = bytes[i];
            i = i + 1;
        } else if not identifier_start(bytes[i]) {
            i = i + 1;
        } else {
            const start = i;
            i = i + 1;
            while i < bytes.len() and (identifier_start(bytes[i]) or (bytes[i] >= 48 and bytes[i] <= 57)) {
                i = i + 1;
            }
            const name = string.from(bytes[start..i]);
            const call = next_call(bytes, i);
            if not keyword(name) and not property(bytes, start) {
                var duplicate = false;
                var j: usize = 0;
                while j < seen.len() {
                    if seen[j] == name {
                        duplicate = true;
                    }
                    j = j + 1;
                }
                if duplicate {
                    if call {
                        j = 0;
                        while j < references.len() {
                            if references[j].name == name {
                                references[j] = ExpressionReference {
                                    name: name,
                                    call: true
                                };
                            }
                            j = j + 1;
                        }
                    }
                } else {
                    seen.push(name);
                    const visible = context.visible(name, script, scopes);
                    if visible {
                        references.push(ExpressionReference {
                            name: name,
                            call: call
                        });
                    }
                    const location: Span = {
                        start: diagnostic_span.start + start,
                        end: diagnostic_span.start + i
                    };
                    if call {
                        helper_warning(name, location, script, diagnostics);
                    }
                    if not visible {
                        context.diagnostic(diagnostics, "unresolved_binding", name, "Unresolved template binding", location);
                    }
                }
            }
        }
    }
    return {
        source: expression,
        references: references
    };
}
