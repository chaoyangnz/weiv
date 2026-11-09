import { Span } from .compiler.source;
import { TemplateDocument, TemplateElement, TemplateSlotOutlet, TemplateExpressionTarget } from .compiler.parser.template.ast;
import { parse } from .compiler.parser.template.parse;
import { TemplateParseError } from .compiler.parser.template.errors;
import .compiler.parser.template.scan;

fn parse_ok(source: string): TemplateDocument {
    return parse(source.bytes()) catch (code) {
        panic("Expected dynamic template to parse");
    };
}

fn expect_error(source: string, expected: TemplateParseError): void {
    const document = parse(source.bytes()) catch (code) {
        assert(code == expected);
        return;
    };
    assert(false);
}

fn expect_span(actual: Span, start: usize, end: usize): void {
    assert(actual.start == start);
    assert(actual.end == end);
}

fn expect_source(source: string, actual: Span, expected: string): void {
    assert(scan.equals(source.bytes(), actual, expected));
}

fn element_at(document: &const TemplateDocument, id: usize): TemplateElement {
    return switch document.nodes[id].payload {
        .element(value) => value;
        _ => {
            panic("Expected element");
        }
    };
}

fn slot_at(document: &const TemplateDocument, id: usize): TemplateSlotOutlet {
    return switch document.nodes[id].payload {
        .slot_outlet(value) => value;
        _ => {
            panic("Expected slot outlet");
        }
    };
}

test "interpolation separates adjacent text and retains full delimiters" {
    const source = "<p>A{{  x + 1  }}B{{y}}</p>";
    const document = parse_ok(source);
    assert(document.nodes.len() == 5);
    assert(document.nodes[0].subtree_end == 5);
    expect_span(document.nodes[2].span, 4, 17);
    assert(document.nodes[2].subtree_end == 3);
    switch document.nodes[2].payload {
        .interpolation(expression) => {
            expect_source(source, expression, "x + 1");
        }
        _ => {
            assert(false);
        }
    }
    switch document.nodes[4].payload {
        .interpolation(expression) => {
            expect_source(source, expression, "y");
        }
        _ => {
            assert(false);
        }
    }
}

test "interpolation empty whitespace and UTF-8 expressions match reference" {
    const source = "{{}}{{ \t }}{{ café 🌱 }}";
    const document = parse_ok(source);
    assert(document.nodes.len() == 3);
    switch document.nodes[0].payload {
        .interpolation(expression) => {
            expect_source(source, expression, "");
        }
        _ => {
            assert(false);
        }
    }
    switch document.nodes[1].payload {
        .interpolation(expression) => {
            expect_source(source, expression, "");
        }
        _ => {
            assert(false);
        }
    }
    switch document.nodes[2].payload {
        .interpolation(expression) => {
            expect_source(source, expression, "café 🌱");
        }
        _ => {
            assert(false);
        }
    }
}

test "interpolation uses the first close pair rather than a JavaScript lexer" {
    const source = "{{ \"}}\" }}";
    const document = parse_ok(source);
    assert(document.nodes.len() == 2);
    expect_span(document.nodes[0].span, 0, 6);
    switch document.nodes[0].payload {
        .interpolation(expression) => {
            expect_source(source, expression, "\"");
        }
        _ => {
            assert(false);
        }
    }
}

test "unterminated interpolation wins over missing parent closer" {
    expect_error("{{", TemplateParseError.unterminated_interpolation);
    expect_error("<p>{{x</p>", TemplateParseError.unterminated_interpolation);
    expect_error("<p>{{ x }", TemplateParseError.unterminated_interpolation);
}

test "if else and for directives are separate from ordinary attributes" {
    const source = "<p class=\"x\" #if=\" ready \" #for=\" item in items \" #else/>";
    const document = parse_ok(source);
    const element = element_at(&document, 0);
    assert(element.attributes_count == 1);
    assert(element.directives_start == 0);
    assert(element.directives_count == 3);
    switch document.directives[0].payload {
        .if_expr(expression) => {
            expect_source(source, expression, " ready ");
        }
        _ => {
            assert(false);
        }
    }
    switch document.directives[1].payload {
        .for_expr(loop) => {
            expect_source(source, loop.item_name, "item");
            expect_source(source, loop.iterable_expr, "items");
        }
        _ => {
            assert(false);
        }
    }
    switch document.directives[2].payload {
        .else_branch => {}
        _ => {
            assert(false);
        }
    }
    expect_source(source, document.directives[0].span, "#if=\" ready \"");
}

test "for separator uses the first literal space-in-space" {
    const source = "<p #for=\"item in left in right\"/>";
    const document = parse_ok(source);
    switch document.directives[0].payload {
        .for_expr(loop) => {
            expect_source(source, loop.item_name, "item");
            expect_source(source, loop.iterable_expr, "left in right");
        }
        _ => {
            assert(false);
        }
    }
    expect_error("<p #for=\"item\tin\titems\"/>", TemplateParseError.invalid_directive);
    expect_error("<p #for=\" in items\"/>", TemplateParseError.invalid_directive);
    expect_error("<p #for=\"item in \"/>", TemplateParseError.invalid_directive);
}

test "canonical events and bindings retain targets expressions and spans" {
    const source = "<p @click=\"go()\" :value=\"model\"/>";
    const document = parse_ok(source);
    const element = element_at(&document, 0);
    assert(element.attributes_count == 0);
    assert(element.directives_count == 2);
    switch document.directives[0].payload {
        .event(event) => {
            expect_source(source, event.name, "click");
            expect_source(source, event.expression, "go()");
            assert(not event.deprecated_syntax);
        }
        _ => {
            assert(false);
        }
    }
    switch document.directives[1].payload {
        .bind(binding) => {
            expect_source(source, binding.name, "value");
            expect_source(source, binding.expression, "model");
            assert(not binding.deprecated_syntax);
        }
        _ => {
            assert(false);
        }
    }
    expect_source(source, document.directives[0].span, "@click=\"go()\"");
    expect_source(source, document.directives[1].span, ":value=\"model\"");
}

test "legacy event and binding names preserve deprecation and empty targets" {
    const source = "<p on:=\"\" bind:=\"\"/>";
    const document = parse_ok(source);
    switch document.directives[0].payload {
        .event(event) => {
            assert(event.deprecated_syntax);
            expect_source(source, event.name, "");
            expect_source(source, event.expression, "");
        }
        _ => {
            assert(false);
        }
    }
    switch document.directives[1].payload {
        .bind(binding) => {
            assert(binding.deprecated_syntax);
            expect_source(source, binding.name, "");
        }
        _ => {
            assert(false);
        }
    }
}

test "recognized directives require values and canonical targets" {
    const inputs: [10]string = ["<p #if/>", "<p #else=\"x\"/>", "<p #for/>", "<p @click/>", "<p :value/>", "<p on:click/>", "<p bind:value/>", "<p @=\"x\"/>", "<p :=\"x\"/>", "<p #for=\"items\"/>"];
    for source in inputs {
        expect_error(source, TemplateParseError.invalid_directive);
    }
}

test "slot assignment requires a nonempty name and no value" {
    const source = "<Header slot:title/>";
    const document = parse_ok(source);
    switch document.directives[0].payload {
        .slot_assign(name) => {
            expect_source(source, name, "title");
        }
        _ => {
            assert(false);
        }
    }
    expect_source(source, document.directives[0].span, "slot:title");
    expect_error("<p slot:/>", TemplateParseError.invalid_directive);
    expect_error("<p slot:title=\"x\"/>", TemplateParseError.invalid_directive);
}

test "directive ranges remain contiguous for nested and sibling elements" {
    const document = parse_ok("<a #if=\"a\"><b @click=\"b\" :x=\"c\"/></a><c #else/>");
    const parent = element_at(&document, 0);
    const child = element_at(&document, 1);
    const sibling = element_at(&document, 2);
    assert(parent.directives_start == 0);
    assert(parent.directives_count == 1);
    assert(child.directives_start == 1);
    assert(child.directives_count == 2);
    assert(sibling.directives_start == 3);
    assert(sibling.directives_count == 1);
    assert(document.directives.len() == 4);
}

test "default outlet fallback uses the normal preorder child range" {
    const document = parse_ok("<slot><b>fallback</b>{{other}}</slot><p/>");
    assert(document.nodes.len() == 5);
    const outlet = slot_at(&document, 0);
    if outlet.name is name {
        assert(false);
    }
    assert(document.nodes[0].subtree_end == 4);
    assert(document.nodes[1].subtree_end == 3);
    assert(document.nodes[3].subtree_end == 4);
    assert(document.nodes[4].subtree_end == 5);
    expect_span(document.nodes[0].span, 0, 37);
}

test "named self-closing outlet preserves original name attribute ranges" {
    const source = "<slot name=\"header\"/>";
    const document = parse_ok(source);
    const outlet = slot_at(&document, 0);
    if outlet.name is name {
        expect_source(source, name, "header");
    } else {
        assert(false);
    }
    assert(outlet.attributes_start == 0);
    assert(outlet.attributes_count == 1);
    expect_source(source, document.attributes[0].name, "name");
    assert(document.nodes[0].subtree_end == 1);
}

test "empty explicit slot names are present and duplicates are still rejected" {
    const document = parse_ok("<slot name=\"\"/>");
    const outlet = slot_at(&document, 0);
    if outlet.name is name {
        assert(name.start == name.end);
    } else {
        assert(false);
    }
    expect_error("<slot name=\"\" name=\"x\"/>", TemplateParseError.invalid_slot_outlet);
}

test "slot outlets reject other attributes missing values and directives" {
    expect_error("<slot name/>", TemplateParseError.invalid_slot_outlet);
    expect_error("<slot class=\"x\"/>", TemplateParseError.invalid_slot_outlet);
    expect_error("<slot name=\"x\" name=\"y\"/>", TemplateParseError.invalid_slot_outlet);
    expect_error("<slot #if=\"yes\"/>", TemplateParseError.invalid_slot_outlet);
    expect_error("<slot slot:header/>", TemplateParseError.invalid_slot_outlet);
}

test "slot validation follows child parsing but directive splitting happens first" {
    expect_error("<slot class=\"x\"><b></slot>", TemplateParseError.mismatched_close_tag);
    expect_error("<slot #if></slot>", TemplateParseError.invalid_directive);
    expect_error("<slot @click=\"go\">{{", TemplateParseError.unterminated_interpolation);
    expect_error("<slot class=\"x\">", TemplateParseError.mismatched_close_tag);
}

test "slot fallback child attributes and sibling ranges survive finalization" {
    const source = "<slot name=\"head\"><b id=\"fallback\"/></slot><p id=\"after\"/>";
    const document = parse_ok(source);
    const outlet = slot_at(&document, 0);
    assert(outlet.attributes_start == 0);
    assert(outlet.attributes_count == 1);
    const child = element_at(&document, 1);
    assert(child.attributes_start == 1);
    assert(child.attributes_count == 1);
    const sibling = element_at(&document, 2);
    assert(sibling.attributes_start == 2);
    assert(sibling.attributes_count == 1);
    expect_source(source, document.attributes[child.attributes_start].name, "id");
}
