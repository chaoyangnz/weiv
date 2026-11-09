// Operation: lexical inputs + source -> validated evaluator functions and exact mappings.
import { Span } from .compiler.source;
import { TemplateFunctionInputs, TemplateFunctions, TemplateFunctionRecord } from .compiler.lower.template_functions;
import { analyze_module_state_raw, handler_supported, handler_kind } from .ffi.script_backend;
import std.json;
import { Value } from std.json;
import { decode } from .compiler.sema.decode_mutation_probe;

pub enum TemplateFunctionError {
    backend_failure;
    invalid_backend_response;
    reserved_identifier;
}
fn write(output: &List<u8>, text: string): void {
    for byte in text.bytes() {
        output.push(byte);
    }
}
fn contains(names: &const List<string>, name: string): bool {
    var i: usize = 0;
    while i < names.len() {
        if names[i] == name {
            return true;
        }
        i = i + 1;
    }
    return false;
}
fn reserved(name: string): bool {
    const bytes = name.bytes();
    return bytes.len() >= 7 and bytes[..7] == "__weiv_".bytes();
}

// Public primitive shared by collection and future runtime evaluator planning.
pub fn append(output: &List<u8>, source: string, locals: &const List<string>, script_names: &const List<string>, argument: ?string): Span ! TemplateFunctionError {
    write(output, "(__weiv_context");
    if argument is name {
        write(output, ",__weiv_argument");
    }
    write(output, ")=>{\n");
    if argument is name {
        if not contains(script_names, name) and not contains(locals, name) {
            write(output, $"const {name}=__weiv_argument;\n");
        }
    }
    var i: usize = 0;
    while i < locals.len() {
        const name = string.from(locals[i].bytes());
        if reserved(name) {
            throw TemplateFunctionError.reserved_identifier;
        }
        var shadowed = false;
        var j = i + 1;
        while j < locals.len() {
            if locals[j] == name {
                shadowed = true;
            }
            j = j + 1;
        }
        if not shadowed {
            const value: Value = .string(name);
            const key = json.encode(&value);
            write(output, $"const {name}=__weiv_context[{key}];\n");
        }
        i = i + 1;
    }
    var kind: u8 = 0;
    if argument is name {
        kind = handler_kind(source) catch (code) {
            throw TemplateFunctionError.backend_failure;
        };
    }
    if kind == 2 {
        write(output, "return ((__weiv_handler)=>typeof __weiv_handler===\"function\"?__weiv_handler(__weiv_argument):__weiv_handler)((");
    } else {
        write(output, "return (");
    }
    const start = output.len();
    write(output, source);
    const end = output.len();
    write(output, ")");
    if kind == 1 {
        write(output, "?.(__weiv_argument)");
    }
    if kind == 2 {
        write(output, ")");
    }
    write(output, ";\n}");
    return {
        start: start,
        end: end
    };
}

pub fn build(source: []const u8, inputs: &const TemplateFunctionInputs, include_pure: bool, prefix: string): TemplateFunctions ! TemplateFunctionError {
    var output = list<u8>();
    write(&output, prefix);
    var records = list<TemplateFunctionRecord>();
    var i: usize = 0;
    while i < inputs.expressions.len() {
        const input = &inputs.expressions[i];
        const expression = string.from(source[input.expression.start..input.expression.end]);
        const supported = handler_supported(expression) catch (code) {
            throw TemplateFunctionError.backend_failure;
        };
        var selected = supported;
        if supported and not include_pure {
            if input.argument is none {
                const probe = $"const __weiv_probe=()=>({expression});";
                const payload = analyze_module_state_raw(probe, "template.ts") catch (code) {
                    throw TemplateFunctionError.backend_failure;
                };
                selected = decode(payload) catch (code) {
                    throw TemplateFunctionError.invalid_backend_response;
                };
            }
        }
        if selected {
            if records.len() > 0 {
                output.push(44);
            }
            const range = try append(&output, expression, &input.locals, &inputs.script_names, input.argument);
            records.push(TemplateFunctionRecord {
                generated: range,
                template: input.expression
            });
        }
        i = i + 1;
    }
    return {
        code: string.from(output.view()),
        records: records
    };
}
