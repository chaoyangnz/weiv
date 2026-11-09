// Operation: script facts and caller selection -> validated Rust cell-name JSON.
import { ComponentUnit } from .compiler.component_unit;
import { CellSelection } from .compiler.backend.browser.emit.cell_selection;
import { JavaScriptError } from .compiler.backend.browser.emit.javascript_errors;
import { append, emit_string } from .compiler.backend.browser.emit.js_module.write_javascript;
import { is_props } from .compiler.backend.browser.classify_tracked_roots;

pub fn is_selected(selection: &const CellSelection, name: string): bool {
    var i: usize = 0;
    while i < selection.local_names.len() {
        if selection.local_names[i] == name {
            return true;
        }
        i = i + 1;
    }
    return false;
}

pub fn select(unit: &const ComponentUnit, selection: &const CellSelection): string ! JavaScriptError {
    var n: usize = 0;
    while n < selection.local_names.len() {
        const name = selection.local_names[n];
        var found = false;
        var b: usize = 0;
        while b < unit.script.facts.bindings.len() {
            const binding = &unit.script.facts.bindings[b];
            if binding.name == name and binding.template_visible and (binding.kind == "mutable" or binding.kind == "immutable") and not is_props(&unit.script.facts, name) {
                found = true;
            }
            b = b + 1;
        }
        if not found {
            throw JavaScriptError.backend_failure;
        }
        n = n + 1;
    }
    var out = list<u8>();
    append(&out, "[");
    var first = true;
    var i: usize = 0;
    while i < unit.script.facts.bindings.len() {
        const binding = &unit.script.facts.bindings[i];
        if is_selected(selection, binding.name) {
            if not first {
                append(&out, ",");
            }
            first = false;
            emit_string(binding.name, &out);
        }
        i = i + 1;
    }
    append(&out, "]");
    return string.from(out.view());
}
