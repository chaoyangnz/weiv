// Operation: script import facts + explicit overrides -> reference-compatible module imports.
import { ScriptFacts, ScriptImport } from .compiler.sema.script_facts;
import { ImportOverride } from .compiler.backend.browser.emit.javascript_module;
import { append } from .compiler.backend.browser.emit.js_module.write_javascript;
import std.mem;

pub fn should_preserve(record: &const ScriptImport, script: &const ScriptFacts): bool {
    if record.kind == "side_effect" {
        return true;
    }
    var i: usize = 0;
    while i < script.bindings.len() {
        const binding = &script.bindings[i];
        if binding.name == record.local_name {
            return binding.kind != "type_only";
        }
        i = i + 1;
    }
    return true;
}
pub fn rewrite_extension(source: string): string {
    const bytes = source.bytes();
    if mem.ends_with(bytes, ".ts".bytes()) {
        const stem = string.from(bytes[..bytes.len() - 3]);
        return $"{stem}.js";
    }
    if mem.ends_with(bytes, ".mts".bytes()) {
        const stem = string.from(bytes[..bytes.len() - 4]);
        return $"{stem}.mjs";
    }
    return source;
}
pub fn direct_specifier(source: string): string {
    const bytes = source.bytes();
    if mem.ends_with(bytes, ".weiv".bytes()) {
        const stem = string.from(bytes[..bytes.len() - 5]);
        return $"{stem}.mjs";
    }
    return rewrite_extension(source);
}
pub fn emit(script: &const ScriptFacts, overrides: &const List<ImportOverride>): string {
    var output = list<u8>();
    var i: usize = 0;
    while i < script.imports.len() {
        const record = &script.imports[i];
        if should_preserve(record, script) {
            var target: ?string = none;
            var o: usize = 0;
            while o < overrides.len() {
                const item = &overrides[o];
                if target is none {
                    if item.source == record.source {
                        target = item.target;
                    }
                }
                o = o + 1;
            }
            var specifier = rewrite_extension(record.source);
            const component = mem.ends_with(record.source.bytes(), ".weiv".bytes());
            if component {
                specifier = direct_specifier(record.source);
            }
            if target is value {
                specifier = value;
            }
            const local = record.local_name;
            if component {
                append(&output, $"import * as {local} from \"{specifier}\";\n");
            } else if record.kind == "side_effect" {
                append(&output, $"import \"{specifier}\";\n");
            } else if record.kind == "default" {
                append(&output, $"import __weiv_import_{local} from \"{specifier}\";\n");
            } else if record.kind == "namespace" {
                append(&output, $"import * as __weiv_import_{local} from \"{specifier}\";\n");
            } else if record.kind == "named" {
                if record.imported_name is name {
                    append(&output, "import { ");
                    append(&output, $"{name} as __weiv_import_{local}");
                    append(&output, " } from ");
                    append(&output, $"\"{specifier}\";\n");
                }
            }
        }
        i = i + 1;
    }
    if output.len() > 0 {
        output.push(10);
    }
    return string.from(output.view());
}
