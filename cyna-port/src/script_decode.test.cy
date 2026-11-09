import { decode } from .compiler.sema.decode_script_facts;
import { ScriptDecodeError } from .compiler.sema.script_json;
import { DecodedScript } from .compiler.sema.decoded_script;
import { analyze_raw } from .ffi.script_backend;

fn empty_payload(): string {
    return "{\"ok\":true,\"source_path\":\"fixture.ts\",\"transpiled_code\":\"code\",\"props\":null,\"imports\":[],\"bindings\":[],\"state_analysis\":null,\"diagnostics\":[]}";
}
fn binding_payload(): string {
    return "{\"name\":\"x\",\"kind\":\"mutable\",\"exported\":true,\"template_visible\":true,\"callable\":false,\"type_annotation\":\"number\",\"span_start\":1,\"span_end\":2}";
}

fn envelope(props: string, imports: string, bindings: string, state: string, diagnostics: string): string {
    return $"\{\"ok\":true,\"source_path\":\"fixture.ts\",\"transpiled_code\":\"code\",\"props\":{props},\"imports\":{imports},\"bindings\":{bindings},\"state_analysis\":{state},\"diagnostics\":{diagnostics}\}";
}

fn bindings_response(bindings: string): string {
    return envelope("null", "[]", bindings, "null", "[]");
}

fn decoded(source: string): DecodedScript {
    return decode(source) catch (code) {
        panic("Expected script-fact decoding");
    };
}

fn expect_error(source: string, expected: ScriptDecodeError): void {
    const result = decode(source) catch (code) {
        assert(code == expected);
        return;
    };
    assert(false);
}

test "empty nullable response has owned facts and separate code" {
    const result = decoded(empty_payload());
    assert(result.facts.ok);
    assert(result.facts.source_path == "fixture.ts");
    assert(result.transpiled_code == "code");
    if result.facts.props is props {
        assert(false);
    }
    assert(result.facts.bindings.len() == 0);
    assert(result.facts.imports.len() == 0);
    assert(result.facts.diagnostics.len() == 0);
    assert(result.facts.state_facts.helpers.len() == 0);
    assert(result.facts.state_facts.mutations.len() == 0);
    assert(result.facts.state_facts.aliases.len() == 0);
    assert(result.facts.state_facts.callback_registrations.len() == 0);
}

test "binding fields and source spans are decoded without losing flags" {
    const payload = binding_payload();
    const bindings = $"[{payload}]";
    const result = decoded(bindings_response(bindings));
    assert(result.facts.bindings.len() == 1);
    const binding = result.facts.bindings[0];
    assert(binding.name == "x");
    assert(binding.kind == "mutable");
    assert(binding.exported);
    assert(binding.template_visible);
    assert(not binding.callable);
    assert(binding.span.start == 1);
    assert(binding.span.end == 2);
    if binding.type_annotation is annotation {
        assert(annotation == "number");
    } else {
        assert(false);
    }
}

test "props and all nullable strings preserve absence and explicit emptiness" {
    const props = "{\"has_props_export\":true,\"props_binding_name\":\"props\",\"props_type_name\":null}";
    const imports = "[{\"source\":\"./state\",\"kind\":\"named\",\"imported_name\":\"\",\"local_name\":\"shared\",\"span_start\":0,\"span_end\":0}]";
    const result = decoded(envelope(props, imports, "[]", "null", "[]"));
    if result.facts.props is facts {
        assert(facts.has_props_export);
        if facts.props_binding_name is name {
            assert(name == "props");
        } else {
            assert(false);
        }
        if facts.props_type_name is name {
            assert(false);
        }
    } else {
        assert(false);
    }
    assert(result.facts.imports[0].source == "./state");
    assert(result.facts.imports[0].kind == "named");
    assert(result.facts.imports[0].local_name == "shared");
    if result.facts.imports[0].imported_name is name {
        assert(name == "");
    } else {
        assert(false);
    }
}

test "state object defaults each omitted collection to empty" {
    const result = decoded(envelope("null", "[]", "[]", "{}", "[]"));
    assert(result.facts.state_facts.helpers.len() == 0);
    assert(result.facts.state_facts.mutations.len() == 0);
    assert(result.facts.state_facts.aliases.len() == 0);
    assert(result.facts.state_facts.callback_registrations.len() == 0);
}

test "helper records preserve string lists flags and ordering" {
    const state = "{\"helpers\":[{\"name\":\"tick\",\"kind\":\"function\",\"span_start\":2,\"span_end\":8,\"reads\":[\"count\",\"other\"],\"writes\":[\"count\"],\"calls\":[\"notify\"],\"async_flag\":true,\"returns_expression_only\":false,\"contains_external_reads\":true,\"contains_side_effects\":true}]}";
    const result = decoded(envelope("null", "[]", "[]", state, "[]"));
    assert(result.facts.state_facts.helpers.len() == 1);
    const helper = &result.facts.state_facts.helpers[0];
    assert(helper.name == "tick");
    assert(helper.kind == "function");
    assert(helper.span.start == 2);
    assert(helper.span.end == 8);
    assert(helper.reads.len() == 2);
    assert(helper.reads[0] == "count");
    assert(helper.reads[1] == "other");
    assert(helper.writes[0] == "count");
    assert(helper.calls[0] == "notify");
    assert(helper.async_flag);
    assert(not helper.returns_expression_only);
    assert(helper.contains_external_reads);
    assert(helper.contains_side_effects);
}

test "mutation alias and callback records map all source and ownership facts" {
    const state = "{\"mutations\":[{\"binding\":\"state\",\"kind\":\"assignment\",\"span_start\":1,\"span_end\":9,\"statement_position\":true,\"member_path\":\"count\",\"inside_callback\":true,\"callback_owned_candidate\":false}],\"aliases\":[{\"alias\":\"copy\",\"target\":\"state\",\"kind\":\"local\",\"span_start\":2,\"span_end\":4}],\"callback_registrations\":[{\"callee\":\"setTimeout\",\"callback_kind\":\"arrow\",\"callback_span_start\":3,\"callback_span_end\":7,\"owned_candidate\":true,\"reason\":\"local\"}]}";
    const result = decoded(envelope("null", "[]", "[]", state, "[]"));
    const mutation = result.facts.state_facts.mutations[0];
    assert(mutation.binding == "state");
    assert(mutation.kind == "assignment");
    assert(mutation.span.start == 1);
    assert(mutation.span.end == 9);
    assert(mutation.statement_position);
    assert(mutation.inside_callback);
    assert(not mutation.callback_owned_candidate);
    if mutation.member_path is path {
        assert(path == "count");
    } else {
        assert(false);
    }
    const alias = result.facts.state_facts.aliases[0];
    assert(alias.alias == "copy");
    assert(alias.target == "state");
    assert(alias.kind == "local");
    assert(alias.span.start == 2);
    assert(alias.span.end == 4);
    const callback = result.facts.state_facts.callback_registrations[0];
    assert(callback.callee == "setTimeout");
    assert(callback.callback_kind == "arrow");
    assert(callback.span.start == 3);
    assert(callback.span.end == 7);
    assert(callback.owned_candidate);
    assert(callback.reason == "local");
}

test "diagnostic coordinates and nullable codes are independent of ok" {
    const diagnostics = "[{\"severity\":\"error\",\"message\":\"message\",\"span_start\":0,\"span_end\":1,\"line\":4294967295,\"column\":0,\"code\":null}]";
    const result = decoded(envelope("null", "[]", "[]", "null", diagnostics));
    assert(result.facts.ok);
    assert(result.facts.diagnostics.len() == 1);
    const diagnostic = result.facts.diagnostics[0];
    assert(diagnostic.severity == "error");
    assert(diagnostic.message == "message");
    assert(diagnostic.line == 4294967295);
    assert(diagnostic.column == 0);
    if diagnostic.code is code {
        assert(false);
    }
}

test "unknown fields are ignored at the envelope and record levels" {
    const source = "{\"future\":{\"x\":1},\"ok\":true,\"source_path\":\"x\",\"transpiled_code\":\"\",\"props\":null,\"imports\":[],\"bindings\":[],\"state_analysis\":{\"future\":[]},\"diagnostics\":[]}";
    const result = decoded(source);
    assert(result.facts.ok);
    assert(result.facts.source_path == "x");
}

test "malformed JSON and duplicate keys produce decode errors" {
    expect_error("{", ScriptDecodeError.invalid_json);
    expect_error("{} trailing", ScriptDecodeError.invalid_json);
    expect_error("{\"ok\":true,\"ok\":false}", ScriptDecodeError.invalid_json);
}

test "nonobject roots and incorrect field shapes are rejected" {
    expect_error("[]", ScriptDecodeError.wrong_type);
    expect_error("null", ScriptDecodeError.wrong_type);
    expect_error(envelope("[]", "[]", "[]", "null", "[]"), ScriptDecodeError.wrong_type);
    expect_error(envelope("null", "{}", "[]", "null", "[]"), ScriptDecodeError.wrong_type);
    expect_error(envelope("null", "[]", "[false]", "null", "[]"), ScriptDecodeError.wrong_type);
    expect_error(envelope("null", "[]", "[]", "[]", "[]"), ScriptDecodeError.wrong_type);
    expect_error(envelope("null", "[]", "[]", "{\"helpers\":null}", "[]"), ScriptDecodeError.wrong_type);
}

test "required fields include nullable protocol members" {
    expect_error("{}", ScriptDecodeError.missing_field);
    expect_error("{\"ok\":true,\"source_path\":\"x\",\"transpiled_code\":\"\",\"imports\":[],\"bindings\":[],\"state_analysis\":null,\"diagnostics\":[]}", ScriptDecodeError.missing_field);
    expect_error(bindings_response("[{\"name\":\"x\"}]"), ScriptDecodeError.missing_field);
    expect_error(envelope("{\"has_props_export\":true}", "[]", "[]", "null", "[]"), ScriptDecodeError.missing_field);
}

test "unsigned numeric fields reject strings negative fractions and exponents" {
    const numbers: [4]string = ["\"1\"", "-1", "1.0", "1e0"];
    for number in numbers {
        const binding = $"[\{\"name\":\"x\",\"kind\":\"mutable\",\"exported\":false,\"template_visible\":true,\"callable\":false,\"type_annotation\":null,\"span_start\":{number},\"span_end\":2\}]";
        if number == "\"1\"" {
            expect_error(bindings_response(binding), ScriptDecodeError.wrong_type);
        } else {
            expect_error(bindings_response(binding), ScriptDecodeError.invalid_integer);
        }
    }
}

test "unsigned overflow and inverted ranges return errors rather than trapping" {
    const huge = "[{\"name\":\"x\",\"kind\":\"mutable\",\"exported\":false,\"template_visible\":true,\"callable\":false,\"type_annotation\":null,\"span_start\":0,\"span_end\":18446744073709551616}]";
    expect_error(bindings_response(huge), ScriptDecodeError.integer_overflow);
    const inverted = "[{\"name\":\"x\",\"kind\":\"mutable\",\"exported\":false,\"template_visible\":true,\"callable\":false,\"type_annotation\":null,\"span_start\":9,\"span_end\":1}]";
    expect_error(bindings_response(inverted), ScriptDecodeError.invalid_span);
    const line = "[{\"severity\":\"error\",\"message\":\"x\",\"span_start\":0,\"span_end\":0,\"line\":4294967296,\"column\":0,\"code\":null}]";
    expect_error(envelope("null", "[]", "[]", "null", line), ScriptDecodeError.integer_overflow);
}

test "maximum usize spans and zero-length ranges are representable" {
    const binding = "[{\"name\":\"x\",\"kind\":\"mutable\",\"exported\":false,\"template_visible\":true,\"callable\":false,\"type_annotation\":null,\"span_start\":18446744073709551615,\"span_end\":18446744073709551615}]";
    const result = decoded(bindings_response(binding));
    assert(result.facts.bindings[0].span.start == 18446744073709551615);
    assert(result.facts.bindings[0].span.end == 18446744073709551615);
}

test "real Rust response decodes bindings props imports and emitted code" {
    const source = "import { value as shared } from './state'; export interface Props { title: string; } export let props: Props; export const answer: number = 42;";
    const response = analyze_raw(source, "component.ts") catch (code) {
        panic("Expected Rust response");
    };
    const result = decoded(response);
    assert(result.facts.ok);
    assert(result.facts.source_path == "component.ts");
    assert(result.facts.imports.len() == 1);
    assert(result.facts.imports[0].source == "./state");
    assert(result.facts.imports[0].local_name == "shared");
    if result.facts.props is props {
        assert(props.has_props_export);
        if props.props_type_name is name {
            assert(name == "Props");
        } else {
            assert(false);
        }
    } else {
        assert(false);
    }
    assert(result.facts.bindings.len() >= 2);
    assert(result.facts.diagnostics.len() == 0);
    assert(result.transpiled_code != "");
}

test "real Rust syntax diagnostics remain separate from successful transport" {
    const response = analyze_raw("const = ;", "bad.ts") catch (code) {
        panic("Expected Rust diagnostics");
    };
    const result = decoded(response);
    assert(not result.facts.ok);
    assert(result.facts.diagnostics.len() > 0);
    if result.facts.diagnostics[0].code is code {
        assert(code == "script.syntax");
    } else {
        assert(false);
    }
    assert(result.transpiled_code == "");
}

test "decoded fields survive temporary JSON cleanup and repeated decodes" {
    const payload = binding_payload();
    const first = decoded(bindings_response($"[{payload}]"));
    var index: usize = 0;
    while index < 32 {
        const next = decoded(empty_payload());
        assert(next.facts.bindings.len() == 0);
        index = index + 1;
    }
    assert(first.facts.bindings[0].name == "x");
    if first.facts.bindings[0].type_annotation is text {
        assert(text == "number");
    } else {
        assert(false);
    }
    assert(first.transpiled_code == "code");
}
