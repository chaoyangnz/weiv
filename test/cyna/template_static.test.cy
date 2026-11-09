import { Span } from .compiler.source;
import { TemplateDocument, TemplateElement } from .compiler.parser.template.ast;
import { parse } from .compiler.parser.template.parse;
import { TemplateParseError } from .compiler.parser.template.errors;
import { parse as parse_sfc } from .compiler.parser.sfc.parse;

fn parse_ok(source: []const u8): TemplateDocument {
    return parse(source) catch (code) {
        panic("Expected static template to parse");
    };
}

fn expect_span(actual: Span, start: usize, end: usize): void {
    assert(actual.start == start);
    assert(actual.end == end);
}

fn element_at(document: &const TemplateDocument, id: usize): TemplateElement {
    return switch document.nodes[id].payload {
        .element(value) => value;
        _ => {
            panic("Expected element node");
        }
    };
}

fn expect_text(document: &const TemplateDocument, id: usize, start: usize, end: usize): void {
    expect_span(document.nodes[id].span, start, end);
    assert(document.nodes[id].subtree_end == id + 1);
    switch document.nodes[id].payload {
        .text(value) => {
            expect_span(value, start, end);
        }
        _ => {
            assert(false);
        }
    }
}

fn expect_error(source: string, expected: TemplateParseError): void {
    const document = parse(source.bytes()) catch (code) {
        assert(code == expected);
        return;
    };
    assert(false);
}

test "empty and whitespace-only templates have no nodes" {
    const empty = parse_ok("".bytes());
    assert(empty.nodes.len() == 0);
    assert(empty.attributes.len() == 0);
    const whitespace = parse_ok(" \t\n\r ".bytes());
    assert(whitespace.nodes.len() == 0);
}

test "text retains leading and trailing whitespace with UTF-8 byte offsets" {
    const document = parse_ok(" hé🌱 ".bytes());
    assert(document.nodes.len() == 1);
    expect_text(&document, 0, 0, 9);
}

test "empty element has a full source span and a leaf subtree boundary" {
    const document = parse_ok("<div></div>".bytes());
    assert(document.nodes.len() == 1);
    const element = element_at(&document, 0);
    expect_span(element.tag_name, 1, 4);
    expect_span(document.nodes[0].span, 0, 11);
    assert(element.attributes_start == 0);
    assert(element.attributes_count == 0);
    assert(document.nodes[0].subtree_end == 1);
}

test "preorder boundaries enumerate direct children and roots" {
    const document = parse_ok("<div><p>x</p><br>tail</div><hr/>".bytes());
    assert(document.nodes.len() == 6);
    expect_span(document.nodes[0].span, 0, 27);
    assert(document.nodes[0].subtree_end == 5);
    expect_span(document.nodes[1].span, 5, 13);
    assert(document.nodes[1].subtree_end == 3);
    expect_text(&document, 2, 8, 9);
    expect_span(document.nodes[3].span, 13, 17);
    assert(document.nodes[3].subtree_end == 4);
    expect_text(&document, 4, 17, 21);
    expect_span(document.nodes[5].span, 27, 32);
    assert(document.nodes[5].subtree_end == 6);
    var child: usize = 1;
    var children: usize = 0;
    while child < document.nodes[0].subtree_end {
        children = children + 1;
        child = document.nodes[child].subtree_end;
    }
    assert(children == 3);
}

test "whitespace-only child runs are omitted but text runs are preserved" {
    const document = parse_ok("<p> \n <b/> x </p>".bytes());
    assert(document.nodes.len() == 3);
    assert(document.nodes[0].subtree_end == 3);
    expect_span(document.nodes[1].span, 6, 10);
    expect_text(&document, 2, 10, 13);
}

test "attributes retain names values and full source spans" {
    const document = parse_ok("<p id=\"a>b\" disabled data-x=raw></p>".bytes());
    const element = element_at(&document, 0);
    assert(element.attributes_start == 0);
    assert(element.attributes_count == 3);
    assert(document.attributes.len() == 3);
    expect_span(document.attributes[0].name, 3, 5);
    expect_span(document.attributes[0].span, 3, 11);
    if document.attributes[0].value is value {
        expect_span(value, 7, 10);
    } else {
        assert(false);
    }
    expect_span(document.attributes[1].name, 12, 20);
    // Zig consumes whitespace after a Boolean attribute name into its span.
    expect_span(document.attributes[1].span, 12, 21);
    if document.attributes[1].value is value {
        assert(false);
    }
    expect_span(document.attributes[2].name, 21, 27);
    if document.attributes[2].value is value {
        expect_span(value, 28, 31);
    } else {
        assert(false);
    }
}

test "attribute ranges belong to their element and preserve duplicates" {
    const document = parse_ok("<a x=1><b y=2 y=3/></a>".bytes());
    const parent = element_at(&document, 0);
    const child = element_at(&document, 1);
    assert(parent.attributes_start == 0);
    assert(parent.attributes_count == 1);
    assert(child.attributes_start == 1);
    assert(child.attributes_count == 2);
    expect_span(document.attributes[2].name, 14, 15);
}

test "empty unquoted values and whitespace around equals follow Zig" {
    const document = parse_ok("<a x = \"\" y= ></a>".bytes());
    assert(document.attributes.len() == 2);
    if document.attributes[0].value is value {
        expect_span(value, 8, 8);
    } else {
        assert(false);
    }
    if document.attributes[1].value is value {
        expect_span(value, 12, 12);
    } else {
        assert(false);
    }
}

test "self-closing elements and uppercase HTML void tags do not need a closer" {
    const document = parse_ok("<Card/><BR><INPUT disabled>".bytes());
    assert(document.nodes.len() == 3);
    var id: usize = 0;
    while id < document.nodes.len() {
        assert(document.nodes[id].subtree_end == id + 1);
        id = id + 1;
    }
}

test "all fourteen HTML void tags are recognized" {
    const document = parse_ok("<area><base><br><col><embed><hr><img><input><link><meta><param><source><track><wbr>".bytes());
    assert(document.nodes.len() == 14);
    assert(document.nodes[13].subtree_end == 14);
}

test "tag matching is case sensitive and has a name boundary" {
    expect_error("<div></DIV>", TemplateParseError.mismatched_close_tag);
    expect_error("<p></prefix>", TemplateParseError.mismatched_close_tag);
}

test "closing whitespace and boundary suffix retain reference behavior" {
    const document = parse_ok("<p>x</p extra>".bytes());
    assert(document.nodes.len() == 2);
    expect_span(document.nodes[0].span, 0, 14);
    expect_text(&document, 1, 3, 4);
}

test "unexpected root close tag" {
    expect_error("</p>", TemplateParseError.unexpected_close_tag);
    expect_error("<p/></p>", TemplateParseError.unexpected_close_tag);
}

test "missing and mismatched nested close tags" {
    expect_error("<p>", TemplateParseError.mismatched_close_tag);
    expect_error("<p><b></p>", TemplateParseError.mismatched_close_tag);
    expect_error("<p></b>", TemplateParseError.mismatched_close_tag);
    expect_error("<p></p", TemplateParseError.mismatched_close_tag);
}

test "unterminated open and close delimiters" {
    expect_error("<", TemplateParseError.unterminated_tag);
    expect_error("<>", TemplateParseError.unterminated_tag);
    expect_error("<p x=\"unclosed>", TemplateParseError.unterminated_tag);
    expect_error("<p></p ", TemplateParseError.unterminated_tag);
}

test "unknown hash-prefixed names remain ordinary attributes" {
    const document = parse_ok("<p #custom=\"value\"/>".bytes());
    const element = element_at(&document, 0);
    assert(element.attributes_count == 1);
    assert(element.directives_count == 0);
}

test "nesting uses an explicit stack and stable arena indices" {
    var source = list<u8>();
    var i: usize = 0;
    while i < 2048 {
        for byte in "<a>".bytes() {
            source.push(byte);
        }
        i = i + 1;
    }
    i = 0;
    while i < 2048 {
        for byte in "</a>".bytes() {
            source.push(byte);
        }
        i = i + 1;
    }
    const document = parse_ok(source.view());
    assert(document.nodes.len() == 2048);
    assert(document.nodes[0].subtree_end == 2048);
    assert(document.nodes[2047].subtree_end == 2048);
    expect_span(document.nodes[0].span, 0, source.len());
    expect_span(document.nodes[2047].span, 6141, 6148);
}

test "SFC handoff uses template-relative source spans" {
    const source = "<template><h1>Hello</h1></template><script lang=\"ts\"></script>";
    const sections = parse_sfc(source.bytes()) catch (code) {
        panic("Expected SFC to parse");
    };
    const bytes = source.bytes();
    const template = bytes[sections.template.content_span.start..sections.template.content_span.end];
    const document = parse_ok(template);
    assert(document.nodes.len() == 2);
    expect_span(document.nodes[0].span, 0, 14);
    expect_text(&document, 1, 4, 9);
    expect_span(element_at(&document, 0).tag_name, 1, 3);
}
