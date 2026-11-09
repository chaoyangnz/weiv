// Operation: one binding + typed evaluator call -> reference DOM update statements.
import { append, emit_html_string, indent } from .compiler.backend.browser.emit.js_module.write_javascript;
import std.mem;
pub fn suffix(value: string): string {
    var output = list<u8>();
    var i: usize = 0;
    for byte in value.bytes() {
        const alpha = (byte >= 65 and byte <= 90) or (byte >= 97 and byte <= 122);
        if alpha or byte == 95 or (i > 0 and byte >= 48 and byte <= 57) {
            output.push(byte);
        } else {
            output.push(95);
        }
        i = i + 1;
    }
    if output.len() == 0 {
        return "value";
    }
    return string.from(output.view());
}
fn line(out: &List<u8>, depth: usize, value: string): void {
    indent(depth, out);
    append(out, value);
    append(out, "\n");
}
pub fn emit(target: string, call: string, static_value: ?string, id: usize, out: &List<u8>): void {
    const fragment = suffix(target);
    const v = $"__value_{id}_{fragment}";
    const n = $"__next_{id}_{fragment}";
    const ref = $"refs[{id}]";
    line(out, 1, $"const {v} = {call};");
    if target == "class" {
        if static_value is text {
            const s = $"__static_{id}_{fragment}";
            const d = $"__dynamic_{id}_{fragment}";
            indent(1, out);
            append(out, $"const {s} = ");
            emit_html_string(text, out);
            append(out, ".trim();\n");
            line(out, 1, $"const {d} = {v} === false || {v} === true || {v} === null || {v} === undefined ? \"\" : String({v}).trim();");
            line(out, 1, $"const {n} = [{s}, {d}].filter(Boolean).join(\" \");");
            line(out, 1, $"if ({n}) \{");
            line(out, 2, $"{ref}.setAttribute(\"class\", {n});");
            line(out, 1, $"\} else if ({ref}.hasAttribute(\"class\")) \{");
            line(out, 2, $"{ref}.removeAttribute(\"class\");");
            line(out, 1, "}");
            return;
        }
    }
    if target == "checked" or target == "disabled" or target == "selected" {
        const has = $"__has_attr_{id}_{fragment}";
        line(out, 1, $"const {n} = Boolean({v});");
        line(out, 1, $"if ({ref}.{target} !== {n}) \{");
        line(out, 2, $"{ref}.{target} = {n};");
        line(out, 1, "}");
        line(out, 1, $"const {has} = {ref}.hasAttribute(\"{target}\");");
        line(out, 1, $"if ({n}) \{");
        line(out, 2, $"if (!{has}) \{ {ref}.setAttribute(\"{target}\", \"\"); \}");
        line(out, 1, "} else {");
        line(out, 2, $"if ({has}) \{ {ref}.removeAttribute(\"{target}\"); \}");
        line(out, 1, "}");
        return;
    }
    if target == "value" {
        const str = $"__next_string_{id}_{fragment}";
        line(out, 1, $"const {n} = {v} ?? \"\";");
        line(out, 1, $"const {str} = String({n});");
        line(out, 1, $"if ({ref}.value !== {str}) \{");
        line(out, 2, $"{ref}.value = {str};");
        line(out, 1, "}");
        line(out, 1, $"{ref}.setAttribute(\"value\", {str});");
        return;
    }
    if target == "style" {
        line(out, 1, $"if ({v} === false || {v} === null || {v} === undefined) \{");
        line(out, 2, $"if ({ref}.hasAttribute(\"style\")) \{ {ref}.removeAttribute(\"style\"); \}");
        line(out, 1, "} else {");
        line(out, 2, $"{ref}.style.cssText = {v} === true ? \"\" : String({v});");
        line(out, 1, "}");
        return;
    }
    if mem.starts_with(target.bytes(), "aria-".bytes()) {
        line(out, 1, $"if ({v} === null || {v} === undefined) \{");
        line(out, 2, $"{ref}.removeAttribute(\"{target}\");");
        line(out, 1, "} else {");
        line(out, 2, $"{ref}.setAttribute(\"{target}\", String({v}));");
        line(out, 1, "}");
        return;
    }
    line(out, 1, $"if ({v} === false || {v} === null || {v} === undefined) \{");
    line(out, 2, $"if ({ref}.hasAttribute(\"{target}\")) \{ {ref}.removeAttribute(\"{target}\"); \}");
    line(out, 1, $"\} else if ({v} === true) \{");
    line(out, 2, $"if (!{ref}.hasAttribute(\"{target}\")) \{ {ref}.setAttribute(\"{target}\", \"\"); \}");
    line(out, 1, "} else {");
    line(out, 2, $"{ref}.setAttribute(\"{target}\", String({v}));");
    line(out, 1, "}");
}
