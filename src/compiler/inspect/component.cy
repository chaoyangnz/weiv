// Operation: complete or partial component compilation -> reference text and JSON inspection.
import { ComponentCompileReport, ComponentUnit } from .compiler.component_unit;
import { CompilationDiagnostic, CompilationStage, SourceOrigin } from .compiler.diagnostics;
import { TemplateDocument, TemplateDirective } from .compiler.parser.template.ast;
import { NormalizedDocument } from .compiler.parser.template.normalized;
import { ScriptFacts } from .compiler.sema.script_facts;
import { TemplateBindings } from .compiler.sema.template_bindings;
import { BrowserComponent } from .compiler.backend.browser.component;
import { build as build_browser } from .compiler.backend.browser.build_component;
import { format as format_invalidation_graph } from .compiler.inspect.invalidation_graph;
import { Span } from .compiler.source;
import { append, emit_string } from .compiler.backend.browser.emit.js_module.write_javascript;
import std.mem;

fn stage_name(value: CompilationStage): string {
    return switch value {
        .sfc_parse => "sfc_parse";
        .template_parse => "template_parse";
        .template_normalize => "template_normalize";
        .script_backend => "script_backend";
        .script_decode => "script_decode";
        .script_facts => "script_facts";
        .binding => "binding";
        .lowering => "lowering";
        .emit => "emit";
    };
}

fn text(source: []const u8, span: Span): string {
    return string.from(source[span.start..span.end]);
}

fn indent(out: &List<u8>, depth: usize): void {
    var i: usize = 0;
    while i < depth {
        append(out, "  ");
        i = i + 1;
    }
}

fn children_count(document: &const TemplateDocument, start: usize, end: usize): usize {
    var count: usize = 0;
    var cursor = start;
    while cursor < end {
        count = count + 1;
        cursor = document.nodes[cursor].subtree_end;
    }
    return count;
}

fn bool_text(value: bool): string {
    if value {
        return "true";
    }
    return "false";
}

fn raw_tag(source: []const u8, document: &const TemplateDocument, raw_id: usize): string {
    const node = &document.nodes[raw_id];
    switch node.payload {
        .element(element) => {
            return text(source, element.tag_name);
        }
        _ => {
            return "";
        }
    }
}

fn raw_slot_name(document: &const TemplateDocument, raw_id: usize): ?Span {
    const node = &document.nodes[raw_id];
    switch node.payload {
        .slot_outlet(value) => {
            return value.name;
        }
        _ => {
            return none;
        }
    }
}

fn append_normalized_directive(
    source: []const u8,
    directive: &const TemplateDirective,
    out: &List<u8>
): void {
    switch directive.payload {
        .bind(value) => {
            const name = text(source, value.name);
            const expression = text(source, value.expression);
            append(out, $"directive bind:{name}=\"{expression}\"\n");
        }
        .event(value) => {
            const name = text(source, value.name);
            const expression = text(source, value.expression);
            append(out, $"directive on:{name}=\"{expression}\"\n");
        }
        .slot_assign(name_span) => {
            const name = text(source, name_span);
            append(out, $"directive slot:{name}\n");
        }
        .if_expr(_) => {}
        .else_branch => {}
        .for_expr(_) => {}
    }
}

fn append_normalized_nodes(
    source: []const u8,
    document: &const TemplateDocument,
    normalized: &const NormalizedDocument,
    start: usize,
    end: usize,
    depth: usize,
    out: &List<u8>
): void {
    var cursor = start;
    while cursor < end {
        const node = &normalized.nodes[cursor];
        indent(out, depth);
        switch node.payload {
            .text(span) => {
                append(out, $"text [{span.start}..{span.end}]\n");
            }
            .interpolation(span) => {
                const expression = text(source, span);
                append(out, $"interpolation `{expression}` [{node.span.start}..{node.span.end}]\n");
            }
            .slot_outlet(raw_id) => {
                const slot_name = raw_slot_name(document, raw_id);
                if slot_name is name_span {
                    const name = text(source, name_span);
                    append(out, $"slot name=\"{name}\"\n");
                } else {
                    append(out, "slot <default>\n");
                }
                append_normalized_nodes(source, document, normalized, cursor + 1, node.subtree_end, depth + 1, out);
            }
            .element(element) => {
                const tag = raw_tag(source, document, element.raw_node);
                var child_count: usize = 0;
                var child_cursor = cursor + 1;
                while child_cursor < node.subtree_end {
                    child_count = child_count + 1;
                    child_cursor = normalized.nodes[child_cursor].subtree_end;
                }
                append(out, $"element <{tag}> children={child_count}\n");
                var directive_index = element.directives_start;
                const directive_end = element.directives_start + element.directives_count;
                while directive_index < directive_end {
                    const raw_directive_id = normalized.directive_ids[directive_index];
                    indent(out, depth + 1);
                    append_normalized_directive(source, &document.directives[raw_directive_id], out);
                    directive_index = directive_index + 1;
                }
                append_normalized_nodes(source, document, normalized, cursor + 1, node.subtree_end, depth + 1, out);
            }
            .conditional(value) => {
                const condition = text(source, value.condition);
                append(out, $"conditional if=\"{condition}\"\n");
                indent(out, depth + 1);
                append(out, "consequent\n");
                append_normalized_nodes(source, document, normalized, cursor + 1, value.alternate_start, depth + 2, out);
                if value.alternate_start < node.subtree_end {
                    indent(out, depth + 1);
                    append(out, "alternate\n");
                    append_normalized_nodes(source, document, normalized, value.alternate_start, node.subtree_end, depth + 2, out);
                }
            }
            .for_loop(value) => {
                const item = text(source, value.item_name);
                const iterable = text(source, value.iterable_expr);
                append(out, $"for {item} in {iterable}\n");
                append_normalized_nodes(source, document, normalized, cursor + 1, node.subtree_end, depth + 1, out);
            }
        }
        cursor = node.subtree_end;
    }
}

fn append_script(facts: &const ScriptFacts, out: &List<u8>): void {
    append(out, "Script analysis\n");
    const ok = bool_text(facts.ok);
    append(out, $"  ok: {ok}\n");
    if facts.props is props {
        const exported = bool_text(props.has_props_export);
        append(out, $"  props export: {exported}\n");
        if props.props_type_name is type_name {
            append(out, $"  props type: {type_name}\n");
        }
    }
    const import_count = facts.imports.len();
    append(out, $"  imports: {import_count}\n");
    const binding_count = facts.bindings.len();
    append(out, $"  bindings: {binding_count}\n");
    var i: usize = 0;
    while i < binding_count {
        const binding = &facts.bindings[i];
        append(out, $"    - {binding.name} [{binding.kind}]\n");
        i = i + 1;
    }
    const diagnostic_count = facts.diagnostics.len();
    append(out, $"  diagnostics: {diagnostic_count}\n");
    i = 0;
    while i < diagnostic_count {
        const diagnostic = &facts.diagnostics[i];
        if diagnostic.code is code {
            append(out, $"    - {diagnostic.severity} {code}: {diagnostic.message} [{diagnostic.line}:{diagnostic.column}] [{diagnostic.span.start}..{diagnostic.span.end}]\n");
        } else {
            append(out, $"    - {diagnostic.severity}: {diagnostic.message} [{diagnostic.line}:{diagnostic.column}] [{diagnostic.span.start}..{diagnostic.span.end}]\n");
        }
        i = i + 1;
    }
}

fn append_bindings(bindings: &const TemplateBindings, out: &List<u8>): void {
    append(out, "Binding phase\n");
    const component_ref_count = bindings.component_refs.len();
    append(out, $"  component refs: {component_ref_count}\n");
    var i: usize = 0;
    while i < component_ref_count {
        const record = &bindings.component_refs[i];
        const resolved = bool_text(record.resolved);
        append(out, $"    - {record.tag_name} resolved={resolved}\n");
        i = i + 1;
    }
    const diagnostic_count = bindings.diagnostics.len();
    append(out, $"  binding diagnostics: {diagnostic_count}\n");
    i = 0;
    while i < diagnostic_count {
        const diagnostic = &bindings.diagnostics[i];
        append(out, $"    - {diagnostic.severity} {diagnostic.kind}: {diagnostic.name}: {diagnostic.message} — [{diagnostic.span.start}..{diagnostic.span.end}]\n");
        i = i + 1;
    }
}

fn starts_with(value: []const u8, prefix: []const u8): bool {
    if value.len() < prefix.len() {
        return false;
    }
    var i: usize = 0;
    while i < prefix.len() {
        if value[i] != prefix[i] {
            return false;
        }
        i = i + 1;
    }
    return true;
}

fn contains(value: string, needle: string): bool {
    if mem.index_of(value.bytes(), needle.bytes()) is none {
        return false;
    }
    return true;
}

fn append_proxy_summary(component: &BrowserComponent, out: &List<u8>): void {
    const formatted = format_invalidation_graph(component);
    const bytes = formatted.bytes();
    var roots = list<string>();
    var imported_count: usize = 0;
    var props_count: usize = 0;
    var local_count: usize = 0;
    var in_tracked_roots = false;
    var cursor: usize = 0;
    while cursor < bytes.len() {
        const start = cursor;
        while cursor < bytes.len() and bytes[cursor] != 10 {
            cursor = cursor + 1;
        }
        const line = bytes[start..cursor];
        if cursor < bytes.len() {
            cursor = cursor + 1;
        }
        if starts_with(line, "tracked-roots".bytes()) {
            in_tracked_roots = true;
            continue;
        }
        if line.len() > 0 and line[0] != 32 and not starts_with(line, "invalidation-graph source=".bytes()) {
            in_tracked_roots = false;
            continue;
        }
        if in_tracked_roots and starts_with(line, "  root ".bytes()) {
            const root = string.from(line[2..]);
            roots.push(root);
            if contains(root, "kind=imported-tracked") {
                imported_count = imported_count + 1;
            }
            if contains(root, "kind=prop-tracked") {
                props_count = props_count + 1;
            }
            if contains(root, "kind=local-tracked") {
                local_count = local_count + 1;
            }
        }
    }
    const root_count = roots.len();
    append(out, "Proxy state graph\n");
    append(out, $"  tracked roots: {root_count}\n");
    append(out, $"  root kinds: imported={imported_count} props={props_count} local={local_count}\n");
    var i: usize = 0;
    while i < root_count {
        const root = roots[i];
        append(out, $"    - {root}\n");
        i = i + 1;
    }
}

fn diagnostic_span(report: &const ComponentCompileReport, diagnostic: &const CompilationDiagnostic): ?Span {
    if diagnostic.span is span {
        if diagnostic.origin == SourceOrigin.file {
            return span;
        }
        if report.sfc_document is sfc {
            var offset = 0;
            if diagnostic.origin == SourceOrigin.template {
                offset = sfc.template.content_span.start;
            } else if diagnostic.origin == SourceOrigin.script {
                offset = sfc.script.content_span.start;
            }
            return Span {
                start: offset + span.start,
                end: offset + span.end
            };
        }
        return span;
    }
    return none;
}

fn source_location(source: string, offset: usize): string {
    var line: usize = 1;
    var column: usize = 1;
    var cursor: usize = 0;
    const bytes = source.bytes();
    while cursor < offset and cursor < bytes.len() {
        if bytes[cursor] == 10 {
            line = line + 1;
            column = 1;
        } else {
            column = column + 1;
        }
        cursor = cursor + 1;
    }
    return $"[{line}:{column}]";
}

fn append_json_location(source: string, offset: usize, out: &List<u8>): void {
    var line: usize = 1;
    var column: usize = 1;
    var cursor: usize = 0;
    const bytes = source.bytes();
    while cursor < offset and cursor < bytes.len() {
        if bytes[cursor] == 10 {
            line = line + 1;
            column = 1;
        } else {
            column = column + 1;
        }
        cursor = cursor + 1;
    }
    append(out, "      \"location\": { \"line\": ");
    append(out, $"{line}");
    append(out, ", \"column\": ");
    append(out, $"{column}");
    append(out, " },\n");
}

fn append_compiler_diagnostics(report: &const ComponentCompileReport, out: &List<u8>): void {
    const count = report.diagnostics.len();
    append(out, "Compiler diagnostics\n");
    append(out, $"  total: {count}\n");
    var i: usize = 0;
    while i < count {
        const diagnostic = &report.diagnostics[i];
        const stage = stage_name(diagnostic.stage);
        append(out, $"    - {diagnostic.severity} {diagnostic.code} [{stage}]");
        const span = diagnostic_span(report, diagnostic);
        if span is value {
            const location = source_location(report.source, value.start);
            append(out, $" {location} [{value.start}..{value.end}]");
        }
        if diagnostic.fatal {
            append(out, " fatal");
        }
        append(out, $": {diagnostic.message}\n");
        i = i + 1;
    }
}

pub fn format_unit(unit: ComponentUnit, report: &const ComponentCompileReport): string {
    var out = list<u8>();
    append(&out, "SFC sections\n");
    append(&out, $"  template: {unit.sfc_document.template.content_span.start}..{unit.sfc_document.template.content_span.end}\n");
    append(&out, $"  script:   {unit.sfc_document.script.content_span.start}..{unit.sfc_document.script.content_span.end}\n");
    if unit.sfc_document.style is style {
        append(&out, $"  style:    {style.content_span.start}..{style.content_span.end}\n");
    } else {
        append(&out, "  style:    <none>\n");
    }
    const root_count = children_count(&unit.template_document, 0, unit.template_document.nodes.len());
    append(&out, "Template AST\n");
    append(&out, $"  root nodes: {root_count}\n");
    append(&out, "Normalized template\n");
    const template_span = unit.sfc_document.template.content_span;
    const template_source = unit.source.bytes()[template_span.start..template_span.end];
    append_normalized_nodes(template_source, &unit.template_document, &unit.normalized_template, 0, unit.normalized_template.nodes.len(), 1, &out);
    append_script(&unit.script.facts, &out);
    append_bindings(&unit.template_bindings, &out);
    append_compiler_diagnostics(report, &out);
    var browser = build_browser(unit);
    append_proxy_summary(&browser, &out);
    return string.from(out.view());
}

pub fn format_report(report: &const ComponentCompileReport): string {
    var out = list<u8>();
    if report.sfc_document is sfc {
        append(&out, "SFC sections\n");
        append(&out, $"  template: {sfc.template.content_span.start}..{sfc.template.content_span.end}\n");
        append(&out, $"  script:   {sfc.script.content_span.start}..{sfc.script.content_span.end}\n");
        if sfc.style is style {
            append(&out, $"  style:    {style.content_span.start}..{style.content_span.end}\n");
        } else {
            append(&out, "  style:    <none>\n");
        }
    }
    if report.template_document is document {
        const root_count = children_count(&document, 0, document.nodes.len());
        append(&out, "Template AST\n");
        append(&out, $"  root nodes: {root_count}\n");
    }
    if report.normalized_template is normalized {
        append(&out, "Normalized template\n");
        if report.sfc_document is sfc {
            if report.template_document is document {
                const span = sfc.template.content_span;
                const template_source = report.source.bytes()[span.start..span.end];
                append_normalized_nodes(template_source, &document, &normalized, 0, normalized.nodes.len(), 1, &out);
            }
        }
    }
    if report.script is script {
        append_script(&script.facts, &out);
    }
    if report.template_bindings is bindings {
        append_bindings(&bindings, &out);
    }
    append_compiler_diagnostics(report, &out);
    if report.failure is failure {
        const halted_stage = stage_name(failure.stage);
        append(&out, "Pipeline halt\n");
        append(&out, $"  halted after: {halted_stage}\n");
    }
    return string.from(out.view());
}

fn append_json_diagnostics(report: &const ComponentCompileReport, out: &List<u8>): void {
    var i: usize = 0;
    while i < report.diagnostics.len() {
        const diagnostic = &report.diagnostics[i];
        append(out, "    {\n");
        append(out, "      \"code\": ");
        emit_string(diagnostic.code, out);
        append(out, ",\n      \"severity\": ");
        emit_string(diagnostic.severity, out);
        append(out, ",\n      \"stage\": ");
        emit_string(stage_name(diagnostic.stage), out);
        append(out, ",\n      \"message\": ");
        emit_string(diagnostic.message, out);
        append(out, ",\n      \"sourcePath\": ");
        emit_string(report.source_path, out);
        append(out, ",\n");
        const span = diagnostic_span(report, diagnostic);
        if span is value {
            append(out, "      \"span\": { \"start\": ");
            append(out, $"{value.start}");
            append(out, ", \"end\": ");
            append(out, $"{value.end}");
            append(out, " },\n");
            append_json_location(report.source, value.start, out);
        } else {
            append(out, "      \"span\": null,\n");
            append(out, "      \"location\": null,\n");
        }
        if diagnostic.fatal {
            append(out, "      \"fatal\": true\n");
        } else {
            append(out, "      \"fatal\": false\n");
        }
        if i + 1 < report.diagnostics.len() {
            append(out, "    },\n");
        } else {
            append(out, "    }\n");
        }
        i = i + 1;
    }
}

pub fn format_json(report: &const ComponentCompileReport): string {
    var out = list<u8>();
    append(&out, "{\n  \"sourcePath\": ");
    emit_string(report.source_path, &out);
    append(&out, ",\n  \"haltedAfter\": ");
    if report.failure is failure {
        emit_string(stage_name(failure.stage), &out);
    } else {
        append(&out, "null");
    }
    append(&out, ",\n  \"stages\": {\n");
    if report.sfc_document is value {
        append(&out, "    \"sfc\": true,\n");
    } else {
        append(&out, "    \"sfc\": false,\n");
    }
    if report.template_document is value {
        append(&out, "    \"template\": true,\n");
    } else {
        append(&out, "    \"template\": false,\n");
    }
    if report.normalized_template is value {
        append(&out, "    \"normalizedTemplate\": true,\n");
    } else {
        append(&out, "    \"normalizedTemplate\": false,\n");
    }
    if report.script is value {
        append(&out, "    \"script\": true,\n");
    } else {
        append(&out, "    \"script\": false,\n");
    }
    if report.template_bindings is value {
        append(&out, "    \"binding\": true,\n");
    } else {
        append(&out, "    \"binding\": false,\n");
    }
    if report.lir_document is value {
        append(&out, "    \"lir\": true\n");
    } else {
        append(&out, "    \"lir\": false\n");
    }
    append(&out, "  },\n  \"diagnostics\": [\n");
    append_json_diagnostics(report, &out);
    append(&out, "  ]\n}\n");
    return string.from(out.view());
}

pub fn format(report: &const ComponentCompileReport): string {
    return format_json(report);
}
