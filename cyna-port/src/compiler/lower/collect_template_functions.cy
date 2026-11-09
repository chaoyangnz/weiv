// Operation: paired normalized/raw templates + script facts -> detached lexical inputs.
import { Span } from .compiler.source;
import { TemplateDocument } from .compiler.parser.template.ast;
import { NormalizedDocument } from .compiler.parser.template.normalized;
import { ScriptFacts } from .compiler.sema.script_facts;
import { TemplateFunctionInput, TemplateFunctionInputs } from .compiler.lower.template_functions;
import { text } from .compiler.sema.binding_context;

struct Scope {
    end: usize;
    name: string;
}

pub fn binding_names(script: &const ScriptFacts): List<string> {
    var names = list<string>();
    var i: usize = 0;
    while i < script.bindings.len() {
        const binding = &script.bindings[i];
        if binding.template_visible {
            names.push(binding.name);
        }
        i = i + 1;
    }
    i = 0;
    while i < script.imports.len() {
        const record = &script.imports[i];
        if record.local_name.bytes().len() > 0 {
            names.push(record.local_name);
        }
        i = i + 1;
    }
    return names;
}
fn add(output: &TemplateFunctionInputs, scopes: &const List<Scope>, expression: Span, argument: ?string): void {
    var locals = list<string>();
    var i: usize = 0;
    while i < scopes.len() {
        const scope = &scopes[i];
        locals.push(scope.name);
        i = i + 1;
    }
    output.expressions.push(TemplateFunctionInput {
        expression: expression,
        locals: locals,
        argument: argument
    });
}

pub fn collect(source: []const u8, raw: &const TemplateDocument, normalized: &const NormalizedDocument, script: &const ScriptFacts): TemplateFunctionInputs {
    var output: TemplateFunctionInputs = {
        script_names: binding_names(script),
        expressions: list<TemplateFunctionInput>()
    };
    var scopes = list<Scope>();
    var i: usize = 0;
    while i < normalized.nodes.len() {
        while scopes.len() > 0 and scopes[scopes.len() - 1].end <= i {
            const _ = scopes.pop();
        }
        const node = &normalized.nodes[i];
        switch node.payload {
            .text(value) => {}
            .interpolation(expression) => {
                add(&output, &scopes, expression, none);
            }
            .conditional(branch) => {
                add(&output, &scopes, branch.condition, none);
            }
            .for_loop(loop) => {
                add(&output, &scopes, loop.iterable_expr, none);
                scopes.push(Scope {
                    end: node.subtree_end,
                    name: text(source, loop.item_name)
                });
            }
            .slot_outlet(value) => {}
            .element(element) => {
                const tag = switch raw.nodes[element.raw_node].payload {
                    .element(value) => value.tag_name;
                    _ => {
                        panic("Expected paired raw element");
                    }
                };
                var argument: ?string = "event";
                if tag.end > tag.start and source[tag.start] >= 65 and source[tag.start] <= 90 {
                    argument = "payload";
                }
                var d = element.directives_start;
                while d < element.directives_start + element.directives_count {
                    const directive = &raw.directives[normalized.directive_ids[d]];
                    switch directive.payload {
                        .bind(value) => {
                            add(&output, &scopes, value.expression, none);
                        }
                        .event(value) => {
                            add(&output, &scopes, value.expression, argument);
                        }
                        _ => {}
                    }
                    d = d + 1;
                }
            }
        }
        i = i + 1;
    }
    return output;
}
