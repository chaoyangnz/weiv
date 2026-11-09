// Operation: immutable template/script facts + imported manifests -> bound template facts.
import { Span } from .compiler.source;
import { TemplateDocument, TemplateElement } from .compiler.parser.template.ast;
import { NormalizedDocument, NormalizedElement } from .compiler.parser.template.normalized;
import { ScriptFacts } from .compiler.sema.script_facts;
import { SlotManifest, SlotEntry } from .compiler.sema.slot_manifest;
import { ComponentManifests } from .compiler.sema.component_manifests;
import { TemplateBindings, ComponentRef, ExpressionFacts, TemplateBindingDiagnostic } from .compiler.sema.template_bindings;
import { LoopScope } from .compiler.sema.binding_context;
import .compiler.sema.binding_context as context;
import .compiler.sema.bind_expression;
import .compiler.sema.build_slot_manifest;

struct SeenProvision {
    name: string;
    template_group: bool;
}

fn raw_element(raw: &const TemplateDocument, id: usize): TemplateElement {
    return switch raw.nodes[id].payload {
        .element(value) => value;
        _ => {
            panic("Normalized element must reference its raw element");
        }
    };
}

fn component(name: string): bool {
    const bytes = name.bytes();
    return bytes.len() > 0 and bytes[0] >= 65 and bytes[0] <= 90;
}

fn nonempty_text(source: []const u8, span: Span): bool {
    var i = span.start;
    while i < span.end {
        const byte = source[i];
        if byte != 32 and byte != 9 and byte != 10 and byte != 13 {
            return true;
        }
        i = i + 1;
    }
    return false;
}

fn validate_provisions(source: []const u8, raw: &const TemplateDocument, normalized: &const NormalizedDocument, id: usize, tag: string, catalogs: &const ComponentManifests, diagnostics: &List<TemplateBindingDiagnostic>): void {
    var seen = list<SeenProvision>();
    var child = id + 1;
    const end = normalized.nodes[id].subtree_end;
    while child < end {
        switch normalized.nodes[child].payload {
            .element(element) => {
                const original = raw_element(raw, element.raw_node);
                const group = context.text(source, original.tag_name) == "template";
                var d = element.directives_start;
                while d < element.directives_start + element.directives_count {
                    const directive = &raw.directives[normalized.directive_ids[d]];
                    switch directive.payload {
                        .slot_assign(span) => {
                            const name = context.text(source, span);
                            var found: ?usize = none;
                            var i: usize = 0;
                            while i < seen.len() {
                                const previous = &seen[i];
                                if previous.name == name {
                                    found = i;
                                }
                                i = i + 1;
                            }
                            if found is index {
                                if not (seen[index].template_group and group) {
                                    context.diagnostic(diagnostics, "slot.duplicate_provision", name, "Slot is provided more than once; use <template slot:<name>> to group multi-node content", directive.span);
                                }
                                seen[index] = SeenProvision {
                                    name: name,
                                    template_group: group
                                };
                            } else {
                                seen.push(SeenProvision {
                                    name: name,
                                    template_group: group
                                });
                            }
                        }
                        _ => {}
                    }
                    d = d + 1;
                }
            }
            _ => {}
        }
        child = normalized.nodes[child].subtree_end;
    }
    const manifest_id = catalogs.find(tag);
    if manifest_id is index {
        const manifest = &catalogs.entries[index].manifest;
        var unnamed = false;
        child = id + 1;
        while child < end {
            switch normalized.nodes[child].payload {
                .element(element) => {
                    var assigned = false;
                    var d = element.directives_start;
                    while d < element.directives_start + element.directives_count {
                        const directive = &raw.directives[normalized.directive_ids[d]];
                        switch directive.payload {
                            .slot_assign(span) => {
                                assigned = true;
                                const name = context.text(source, span);
                                if not manifest.has_name(name) {
                                    context.diagnostic(diagnostics, "slot.unknown_name", name, "Child component has no <slot> with this name", directive.span);
                                }
                            }
                            _ => {}
                        }
                        d = d + 1;
                    }
                    if not assigned {
                        unnamed = true;
                    }
                }
                .text(span) => {
                    if nonempty_text(source, span) {
                        unnamed = true;
                    }
                }
                _ => {
                    unnamed = true;
                }
            }
            child = normalized.nodes[child].subtree_end;
        }
        if unnamed and not manifest.has_default() {
            context.diagnostic(diagnostics, "slot.default_not_supported", tag, "Component has no default <slot>; default content is not allowed", normalized.nodes[id].span);
        }
    }
}

fn bind_element(source: []const u8, raw: &const TemplateDocument, normalized: &const NormalizedDocument, id: usize, element: NormalizedElement, script: &const ScriptFacts, catalogs: &const ComponentManifests, scopes: &const List<LoopScope>, output: &TemplateBindings): void {
    const original = raw_element(raw, element.raw_node);
    var a = original.attributes_start;
    while a < original.attributes_start + original.attributes_count {
        const attribute = &raw.attributes[a];
        const name = context.text(source, attribute.name);
        if name == "v-if" {
            context.diagnostic(&output.diagnostics, "directive.vue_structural_syntax", name, "v-if is an inert HTML attribute in Weiv; use #if for a structural conditional", attribute.span);
        } else if name == "v-for" {
            context.diagnostic(&output.diagnostics, "directive.vue_structural_syntax", name, "v-for is an inert HTML attribute in Weiv; use #for for a structural loop", attribute.span);
        }
        a = a + 1;
    }
    const tag = context.text(source, original.tag_name);
    const location = normalized.nodes[id].span;
    if component(tag) {
        const resolved = context.visible(tag, script, scopes);
        output.component_refs.push(ComponentRef {
            tag_name: tag,
            resolved: resolved,
            span: location
        });
        if not resolved {
            context.diagnostic(&output.diagnostics, "unresolved_component", tag, "Unresolved component tag", location);
        }
    }
    var d = element.directives_start;
    while d < element.directives_start + element.directives_count {
        const directive = &raw.directives[normalized.directive_ids[d]];
        switch directive.payload {
            .bind(binding) => {
                if binding.deprecated_syntax {
                    context.diagnostic(&output.diagnostics, "directive.deprecated_syntax", context.text(source, binding.name), "bind: is deprecated; use the canonical :name binding syntax", directive.span);
                }
                output.expressions.push(bind_expression.bind(source, binding.expression, location, script, scopes, &output.diagnostics));
            }
            .event(event) => {
                if event.deprecated_syntax {
                    context.diagnostic(&output.diagnostics, "directive.deprecated_syntax", context.text(source, event.name), "on: is deprecated; use the canonical @event syntax", directive.span);
                }
                output.expressions.push(bind_expression.bind(source, event.expression, location, script, scopes, &output.diagnostics));
            }
            .slot_assign(name) => {}
            _ => {
                panic("Normalized elements must not retain structural directives");
            }
        }
        d = d + 1;
    }
    if component(tag) {
        validate_provisions(source, raw, normalized, id, tag, catalogs, &output.diagnostics);
    }
}

pub fn bind(source: []const u8, raw: &const TemplateDocument, normalized: &const NormalizedDocument, script: &const ScriptFacts, catalogs: &const ComponentManifests): TemplateBindings {
    var report = build_slot_manifest.build(source, raw, normalized);
    var diagnostics = list<TemplateBindingDiagnostic>();
    var i: usize = 0;
    while i < report.duplicates.len() {
        const duplicate = &report.duplicates[i];
        var name = "default";
        if duplicate.name is actual {
            name = actual;
        }
        context.diagnostic(&diagnostics, "slot.duplicate_outlet", name, "Slot outlet declared more than once with the same name", duplicate.span);
        i = i + 1;
    }
    i = 0;
    while i < script.bindings.len() {
        const binding = &script.bindings[i];
        if binding.name == "emit" {
            context.script_diagnostic(&diagnostics, "framework.reserved_binding", "emit", "`emit` is provided by Weiv for component events; declare `export interface Emits` for typing instead of defining `emit` yourself", binding.span);
        }
        i = i + 1;
    }
    report.manifest = SlotManifest {
        entries: list<SlotEntry>()
    }
    @ const own_manifest;
    var output: TemplateBindings = {
        component_refs: list<ComponentRef>(),
        expressions: list<ExpressionFacts>(),
        diagnostics: diagnostics,
        own_slot_manifest: own_manifest
    };
    var scopes = list<LoopScope>();
    i = 0;
    while i < normalized.nodes.len() {
        while scopes.len() > 0 and scopes[scopes.len() - 1].end <= i {
            const _ = scopes.pop();
        }
        const node = normalized.nodes[i];
        switch node.payload {
            .text(span) => {}
            .slot_outlet(raw_id) => {}
            .interpolation(expression) => {
                output.expressions.push(bind_expression.bind(source, expression, node.span, script, &scopes, &output.diagnostics));
            }
            .conditional(branch) => {
                output.expressions.push(bind_expression.bind(source, branch.condition, node.span, script, &scopes, &output.diagnostics));
            }
            .for_loop(loop) => {
                output.expressions.push(bind_expression.bind(source, loop.iterable_expr, node.span, script, &scopes, &output.diagnostics));
                scopes.push(LoopScope {
                    name: context.text(source, loop.item_name),
                    end: node.subtree_end
                });
            }
            .element(element) => {
                bind_element(source, raw, normalized, i, element, script, catalogs, &scopes, &output);
            }
        }
        i = i + 1;
    }
    return output;
}
