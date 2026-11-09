import { Span } from .compiler.source;
import { TemplateDocument } from .compiler.parser.template.ast;
import { parse } from .compiler.parser.template.parse;
import { normalize, NormalizeError } from .compiler.parser.template.normalize;
import { NormalizedDocument, NormalizedElement, NormalizedConditional, NormalizedLoop } from .compiler.parser.template.normalized;
import .compiler.parser.template.scan;

fn parse_ok(source: string): TemplateDocument {
    return parse(source.bytes()) catch (code) {
        panic("Expected template parse");
    };
}

fn normalize_ok(raw: &const TemplateDocument): NormalizedDocument {
    return normalize(raw) catch (code) {
        panic("Expected normalization");
    };
}

fn expect_else_error(source: string): void {
    const raw = parse_ok(source);
    const output = normalize(&raw) catch (code) {
        assert(code == NormalizeError.unexpected_else);
        return;
    };
    assert(false);
}

fn element_at(output: &const NormalizedDocument, id: usize): NormalizedElement {
    return switch output.nodes[id].payload {
        .element(value) => value;
        _ => {
            panic("Expected normalized element");
        }
    };
}

fn conditional_at(output: &const NormalizedDocument, id: usize): NormalizedConditional {
    return switch output.nodes[id].payload {
        .conditional(value) => value;
        _ => {
            panic("Expected conditional");
        }
    };
}

fn loop_at(output: &const NormalizedDocument, id: usize): NormalizedLoop {
    return switch output.nodes[id].payload {
        .for_loop(value) => value;
        _ => {
            panic("Expected loop");
        }
    };
}

fn expect_source(source: string, actual: Span, expected: string): void {
    assert(scan.equals(source.bytes(), actual, expected));
}

test "normalization preserves empty documents" {
    const raw = parse_ok(" \n ");
    const output = normalize_ok(&raw);
    assert(output.nodes.len() == 0);
    assert(output.directive_ids.len() == 0);
}

test "plain nodes preserve raw IDs attributes text interpolation and spans" {
    const source = "<p id=\"x\">Hello {{who}}</p><br>";
    const raw = parse_ok(source);
    const output = normalize_ok(&raw);
    assert(output.nodes.len() == 4);
    assert(output.nodes[0].subtree_end == 3);
    assert(element_at(&output, 0).raw_node == 0);
    assert(element_at(&output, 3).raw_node == 3);
    switch raw.nodes[element_at(&output, 0).raw_node].payload {
        .element(value) => {
            assert(value.attributes_count == 1);
        }
        _ => {
            assert(false);
        }
    }
    switch output.nodes[1].payload {
        .text(value) => {
            expect_source(source, value, "Hello ");
        }
        _ => {
            assert(false);
        }
    }
    switch output.nodes[2].payload {
        .interpolation(value) => {
            expect_source(source, value, "who");
        }
        _ => {
            assert(false);
        }
    }
    assert(output.nodes[0].span.start == raw.nodes[0].span.start);
    assert(output.nodes[0].span.end == raw.nodes[0].span.end);
}

test "if without else has an empty alternate range" {
    const source = "<p #if=\"ready\">yes</p><hr>";
    const raw = parse_ok(source);
    const output = normalize_ok(&raw);
    assert(output.nodes.len() == 4);
    const branch = conditional_at(&output, 0);
    expect_source(source, branch.condition, "ready");
    assert(branch.alternate_start == 3);
    assert(output.nodes[0].subtree_end == 3);
    assert(element_at(&output, 1).raw_node == 0);
    assert(element_at(&output, 1).directives_count == 0);
    assert(element_at(&output, 3).raw_node == 2);
}

test "adjacent else is consumed across omitted whitespace" {
    const source = "<p #if=\"ready\">yes</p> \n <b #else>no</b><hr>";
    const raw = parse_ok(source);
    const output = normalize_ok(&raw);
    assert(output.nodes.len() == 6);
    const branch = conditional_at(&output, 0);
    assert(branch.alternate_start == 3);
    assert(output.nodes[0].subtree_end == 5);
    assert(element_at(&output, 1).raw_node == 0);
    assert(element_at(&output, 3).raw_node == 2);
    assert(element_at(&output, 5).raw_node == 4);
    assert(output.nodes[0].span.end == raw.nodes[0].span.end);
    assert(output.nodes[0].span.end < raw.nodes[2].span.end);
}

test "text and interpolation interrupt else adjacency" {
    expect_else_error("<a #if=\"x\"/>text<b #else/>");
    expect_else_error("<a #if=\"x\"/>{{value}}<b #else/>");
}

test "else cannot pair across parent boundaries" {
    expect_else_error("<div><a #if=\"x\"/></div><b #else/>");
    expect_else_error("<div><a #else/></div>");
    expect_else_error("<slot><a #else/></slot>");
    expect_else_error("<a #else/>");
}

test "for wrapper preserves loop spans and filters structural directives" {
    const source = "<li #for=\" item in items \" @click=\"go\">{{item}}</li>";
    const raw = parse_ok(source);
    const output = normalize_ok(&raw);
    assert(output.nodes.len() == 3);
    const loop = loop_at(&output, 0);
    expect_source(source, loop.item_name, "item");
    expect_source(source, loop.iterable_expr, "items");
    assert(output.nodes[0].subtree_end == 3);
    assert(output.nodes[1].subtree_end == 3);
    const body = element_at(&output, 1);
    assert(body.raw_node == 0);
    assert(body.directives_count == 1);
    assert(output.directive_ids[body.directives_start] == 1);
}

test "if wins over for on the same element" {
    const raw = parse_ok("<p #for=\"item in items\" #if=\"ready\"/>");
    const output = normalize_ok(&raw);
    assert(output.nodes.len() == 2);
    const branch = conditional_at(&output, 0);
    assert(branch.alternate_start == 2);
    assert(element_at(&output, 1).directives_count == 0);
    assert(output.directive_ids.len() == 0);
}

test "for wins over orphan else on the same element" {
    const raw = parse_ok("<p #else #for=\"item in items\"/>");
    const output = normalize_ok(&raw);
    const loop = loop_at(&output, 0);
    assert(output.nodes.len() == 2);
    assert(element_at(&output, 1).directives_count == 0);
}

test "if wins over else on the same element" {
    const raw = parse_ok("<p #else #if=\"ok\"/>");
    const output = normalize_ok(&raw);
    const branch = conditional_at(&output, 0);
    assert(output.nodes.len() == 2);
    assert(branch.alternate_start == 2);
}

test "first repeated if and for directives select wrapper expressions" {
    const source = "<a #if=\"first\" #if=\"second\"/><b #for=\"one in left\" #for=\"two in right\"/>";
    const raw = parse_ok(source);
    const output = normalize_ok(&raw);
    expect_source(source, conditional_at(&output, 0).condition, "first");
    expect_source(source, loop_at(&output, 2).item_name, "one");
    expect_source(source, loop_at(&output, 2).iterable_expr, "left");
    assert(output.directive_ids.len() == 0);
}

test "consumed else with its own if and for stays a plain branch" {
    const raw = parse_ok("<a #if=\"x\"/><b #else #if=\"y\" #for=\"item in items\"/>");
    const output = normalize_ok(&raw);
    assert(output.nodes.len() == 3);
    assert(conditional_at(&output, 0).alternate_start == 2);
    assert(output.nodes[0].subtree_end == 3);
    assert(element_at(&output, 2).directives_count == 0);
}

test "second unpaired else remains an error and branch children are normalized" {
    expect_else_error("<a #if=\"x\"/><b #else/><c #else/>");
    expect_else_error("<a #if=\"x\"/><b #else><c #else/></b>");
    expect_else_error("<a #if=\"x\"><c #else/></a>");
}

test "nonstructural directive IDs preserve order across branches and siblings" {
    const raw = parse_ok("<a #if=\"x\" @click=\"go\" :value=\"model\" slot:head/><b #else on:click=\"old\"/><c bind:value=\"last\"/>");
    const output = normalize_ok(&raw);
    assert(output.directive_ids.len() == 5);
    const yes = element_at(&output, 1);
    const no = element_at(&output, 2);
    const after = element_at(&output, 3);
    assert(yes.directives_start == 0);
    assert(yes.directives_count == 3);
    assert(no.directives_start == 3);
    assert(no.directives_count == 1);
    assert(after.directives_start == 4);
    assert(after.directives_count == 1);
    assert(output.directive_ids[0] == 1);
    assert(output.directive_ids[1] == 2);
    assert(output.directive_ids[2] == 3);
    assert(output.directive_ids[3] == 5);
    assert(output.directive_ids[4] == 6);
}

test "nested loops and conditionals stay inside their parent ranges" {
    const raw = parse_ok("<ul><li #for=\"item in items\"><a #if=\"item.ok\"/><b #else/></li></ul>");
    const output = normalize_ok(&raw);
    assert(output.nodes.len() == 6);
    assert(element_at(&output, 0).raw_node == 0);
    const loop = loop_at(&output, 1);
    assert(element_at(&output, 2).raw_node == 1);
    assert(conditional_at(&output, 3).alternate_start == 5);
    assert(output.nodes[0].subtree_end == 6);
    assert(output.nodes[1].subtree_end == 6);
    assert(output.nodes[2].subtree_end == 6);
    assert(output.nodes[3].subtree_end == 6);
}

test "slot fallback normalizes while retaining outlet identity" {
    const raw = parse_ok("<slot name=\"head\"><a #if=\"x\"/><b #else/></slot><hr>");
    const output = normalize_ok(&raw);
    assert(output.nodes.len() == 5);
    switch output.nodes[0].payload {
        .slot_outlet(id) => {
            assert(id == 0);
        }
        _ => {
            assert(false);
        }
    }
    assert(output.nodes[0].subtree_end == 4);
    assert(conditional_at(&output, 1).alternate_start == 3);
    assert(output.nodes[1].subtree_end == 4);
}

test "empty conditions remain a parser value rather than a normalization error" {
    const source = "<p #if=\"\"/>";
    const raw = parse_ok(source);
    const output = normalize_ok(&raw);
    expect_source(source, conditional_at(&output, 0).condition, "");
}

test "normalization leaves raw arenas unchanged and can run twice" {
    const raw = parse_ok("<a #if=\"ok\" @click=\"go\"/><b #else/>");
    const first = normalize_ok(&raw);
    const second = normalize_ok(&raw);
    assert(raw.nodes.len() == 2);
    assert(raw.directives.len() == 3);
    assert(first.nodes.len() == second.nodes.len());
    assert(first.directive_ids.len() == second.directive_ids.len());
    assert(conditional_at(&first, 0).alternate_start == conditional_at(&second, 0).alternate_start);
    switch raw.nodes[0].payload {
        .element(value) => {
            assert(value.directives_count == 2);
        }
        _ => {
            assert(false);
        }
    }
}

test "deep normalization uses an explicit work stack" {
    var source = list<u8>();
    var i: usize = 0;
    while i < 1024 {
        for byte in "<a #if=\"x\">".bytes() {
            source.push(byte);
        }
        i = i + 1;
    }
    i = 0;
    while i < 1024 {
        for byte in "</a>".bytes() {
            source.push(byte);
        }
        i = i + 1;
    }
    const raw = parse(source.view()) catch (code) {
        panic("Expected deeply nested parse");
    };
    const output = normalize_ok(&raw);
    assert(output.nodes.len() == 2048);
    assert(output.nodes[0].subtree_end == 2048);
    assert(conditional_at(&output, 0).alternate_start == 2048);
    assert(conditional_at(&output, 2046).alternate_start == 2048);
    assert(output.nodes[2047].subtree_end == 2048);
}
