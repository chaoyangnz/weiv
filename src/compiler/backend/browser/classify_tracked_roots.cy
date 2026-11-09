// Operation: immutable script facts -> browser tracking classification; no component ownership.
import { ScriptFacts } from .compiler.sema.script_facts;
import { TrackedKind } from .compiler.backend.browser.tracked_roots;

pub fn is_imported(script: &const ScriptFacts, name: string): bool {
    var i: usize = 0;
    while i < script.imports.len() {
        const record = &script.imports[i];
        if record.local_name == name {
            return true;
        }
        i = i + 1;
    }
    return false;
}
pub fn is_props(script: &const ScriptFacts, name: string): bool {
    if script.props is props {
        if props.props_binding_name is binding {
            return binding == name;
        }
    }
    return false;
}
// Returns the zero-based index of the first visible binding, not a tracking ID.
pub fn find_visible_binding(script: &const ScriptFacts, name: string): ?usize {
    var i: usize = 0;
    while i < script.bindings.len() {
        const binding = &script.bindings[i];
        if binding.template_visible and binding.name == name {
            return i;
        }
        i = i + 1;
    }
    return none;
}
pub fn is_local_tracked(script: &const ScriptFacts, name: string): bool {
    const index = find_visible_binding(script, name);
    if index is none {
        return false;
    }
    const binding = &script.bindings[index];
    if binding.kind != "mutable" and binding.kind != "immutable" {
        return false;
    }
    if binding.callable {
        return false;
    }
    if is_imported(script, name) or is_props(script, name) {
        return false;
    }
    var i: usize = 0;
    while i < script.state_facts.aliases.len() {
        const alias = &script.state_facts.aliases[i];
        if alias.target == name {
            return false;
        }
        i = i + 1;
    }
    i = 0;
    while i < script.state_facts.mutations.len() {
        const mutation = &script.state_facts.mutations[i];
        if mutation.binding == name {
            if mutation.member_path is none {
                return false;
            }
        }
        i = i + 1;
    }
    return true;
}
pub fn kind_by_name(script: &const ScriptFacts, name: string): ?TrackedKind {
    if is_imported(script, name) {
        return TrackedKind.imported_tracked;
    }
    if is_props(script, name) {
        return TrackedKind.prop_tracked;
    }
    if is_local_tracked(script, name) {
        return TrackedKind.local_tracked;
    }
    return none;
}
