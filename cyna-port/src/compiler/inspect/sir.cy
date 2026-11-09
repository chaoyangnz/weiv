// Operation: semantic script and binding facts -> reference text inspection.
import { ScriptFacts } from .compiler.sema.script_facts;
import { TemplateBindings } from .compiler.sema.template_bindings;
import { append } from .compiler.backend.browser.emit.js_module.write_javascript;

pub fn format(source_path: string, script: &const ScriptFacts, bindings: &const TemplateBindings): string {
    var out = list<u8>();
    append(&out, $"SIR source={source_path}\n");
    append(&out, "script\n");
    if script.ok {
        append(&out, "  ok: true\n");
    } else {
        append(&out, "  ok: false\n");
    }
    if script.props is props {
        if props.has_props_export {
            append(&out, "  props export: true\n");
        } else {
            append(&out, "  props export: false\n");
        }
        if props.props_type_name is type_name {
            append(&out, $"  props type: {type_name}\n");
        }
        if props.props_binding_name is binding_name {
            append(&out, $"  props binding: {binding_name}\n");
        }
    }
    const import_count = script.imports.len();
    append(&out, $"  imports: {import_count}\n");
    var i: usize = 0;
    while i < import_count {
        const record = &script.imports[i];
        append(&out, $"    - local={record.local_name} source={record.source}\n");
        i = i + 1;
    }
    const binding_count = script.bindings.len();
    append(&out, $"  bindings: {binding_count}\n");
    i = 0;
    while i < binding_count {
        const record = &script.bindings[i];
        append(&out, $"    - {record.name} kind={record.kind} visible=");
        if record.template_visible {
            append(&out, "true");
        } else {
            append(&out, "false");
        }
        append(&out, " callable=");
        if record.callable {
            append(&out, "true\n");
        } else {
            append(&out, "false\n");
        }
        i = i + 1;
    }
    const script_diagnostic_count = script.diagnostics.len();
    append(&out, $"  diagnostics: {script_diagnostic_count}\n");
    i = 0;
    while i < script_diagnostic_count {
        const diagnostic = &script.diagnostics[i];
        if diagnostic.code is code {
            append(&out, $"    - {diagnostic.severity} {code}: {diagnostic.message} [{diagnostic.line}:{diagnostic.column}] [{diagnostic.span.start}..{diagnostic.span.end}]\n");
        } else {
            append(&out, $"    - {diagnostic.severity}: {diagnostic.message} [{diagnostic.line}:{diagnostic.column}] [{diagnostic.span.start}..{diagnostic.span.end}]\n");
        }
        i = i + 1;
    }
    append(&out, "binding\n");
    const component_ref_count = bindings.component_refs.len();
    append(&out, $"  component refs: {component_ref_count}\n");
    i = 0;
    while i < component_ref_count {
        const record = &bindings.component_refs[i];
        append(&out, $"    - {record.tag_name} resolved=");
        if record.resolved {
            append(&out, "true");
        } else {
            append(&out, "false");
        }
        append(&out, $" [{record.span.start}..{record.span.end}]\n");
        i = i + 1;
    }
    const binding_diagnostic_count = bindings.diagnostics.len();
    append(&out, $"  diagnostics: {binding_diagnostic_count}\n");
    i = 0;
    while i < binding_diagnostic_count {
        const diagnostic = &bindings.diagnostics[i];
        append(&out, $"    - {diagnostic.severity} {diagnostic.kind}: {diagnostic.name}: {diagnostic.message} - [{diagnostic.span.start}..{diagnostic.span.end}]\n");
        i = i + 1;
    }
    return string.from(out.view());
}
