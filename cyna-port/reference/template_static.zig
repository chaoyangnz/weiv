// Optional oracle checks for the same static-template contracts as the Cyna tests.
// zig test --dep parser -Mroot=cyna-port/reference/template_static.zig -Mparser=src/compiler/parser/index.zig
const std = @import("std");
const parser = @import("parser");
const template = parser.template;
const expect = std.testing.expect;
const equal = std.testing.expectEqual;
const allocator = std.testing.allocator;

fn span(actual: parser.sfc.Span, start: usize, end: usize) !void {
    try equal(start, actual.start);
    try equal(end, actual.end);
}

test "static empty whitespace and UTF-8 text" {
    for ([_][]const u8{ "", " \t\n\r " }) |source| {
        var doc = try template.parse(source, allocator);
        defer doc.deinit(allocator);
        try equal(@as(usize, 0), doc.nodes.len);
    }
    var doc = try template.parse(" hé🌱 ", allocator);
    defer doc.deinit(allocator);
    try equal(@as(usize, 1), doc.nodes.len);
    try span(doc.nodes[0].text.span, 0, 9);
}

test "static nested structure root siblings text and void elements" {
    var doc = try template.parse("<div><p>x</p><br>tail</div><hr/>", allocator);
    defer doc.deinit(allocator);
    try equal(@as(usize, 2), doc.nodes.len);
    const root = doc.nodes[0].element;
    try span(root.span, 0, 27);
    try equal(@as(usize, 3), root.children.len);
    try span(root.children[0].element.span, 5, 13);
    try span(root.children[0].element.children[0].text.span, 8, 9);
    try span(root.children[1].element.span, 13, 17);
    try span(root.children[2].text.span, 17, 21);
    try span(doc.nodes[1].element.span, 27, 32);
}

test "static whitespace-only runs are omitted" {
    var doc = try template.parse("<p> \n <b/> x </p>", allocator);
    defer doc.deinit(allocator);
    const children = doc.nodes[0].element.children;
    try equal(@as(usize, 2), children.len);
    try span(children[0].element.span, 6, 10);
    try span(children[1].text.span, 10, 13);
}

test "static attributes preserve quote handling Boolean spans and raw values" {
    var doc = try template.parse("<p id=\"a>b\" disabled data-x=raw></p>", allocator);
    defer doc.deinit(allocator);
    const attributes = doc.nodes[0].element.attributes;
    try equal(@as(usize, 3), attributes.len);
    try span(attributes[0].span, 3, 11);
    try std.testing.expectEqualStrings("a>b", attributes[0].value.?);
    try span(attributes[1].span, 12, 21);
    try expect(attributes[1].value == null);
    try span(attributes[2].span, 21, 31);
    try std.testing.expectEqualStrings("raw", attributes[2].value.?);
}

test "static duplicate and empty attribute values" {
    var doc = try template.parse("<a x=1><b y=2 y=3/></a>", allocator);
    defer doc.deinit(allocator);
    const child = doc.nodes[0].element.children[0].element;
    try equal(@as(usize, 2), child.attributes.len);
    try span(child.attributes[1].span, 14, 17);
    var empty = try template.parse("<a x = \"\" y= ></a>", allocator);
    defer empty.deinit(allocator);
    for (empty.nodes[0].element.attributes) |attribute| {
        try std.testing.expectEqualStrings("", attribute.value.?);
    }
}

test "static void names and close-tag boundary behavior" {
    var doc = try template.parse("<area><base><br><col><embed><hr><img><input><link><meta><param><source><track><wbr>", allocator);
    defer doc.deinit(allocator);
    try equal(@as(usize, 14), doc.nodes.len);
    var upper = try template.parse("<Card/><BR><INPUT disabled>", allocator);
    defer upper.deinit(allocator);
    try equal(@as(usize, 3), upper.nodes.len);
    var closing = try template.parse("<p>x</p extra>", allocator);
    defer closing.deinit(allocator);
    try span(closing.nodes[0].element.span, 0, 14);
}

test "static malformed tags preserve error kinds" {
    for ([_][]const u8{ "</p>", "<p/></p>" }) |source| {
        try std.testing.expectError(error.UnexpectedCloseTag, template.parse(source, allocator));
    }
    for ([_][]const u8{ "<p>", "<p><b></p>", "<p></b>", "<p></p", "<div></DIV>", "<p></prefix>" }) |source| {
        // Scope all reference allocations to this malformed-input case.
        var arena = std.heap.ArenaAllocator.init(allocator);
        defer arena.deinit();
        try std.testing.expectError(error.MismatchedCloseTag, template.parse(source, arena.allocator()));
    }
    for ([_][]const u8{ "<", "<>", "<p x=\"unclosed>", "<p></p " }) |source| {
        var arena = std.heap.ArenaAllocator.init(allocator);
        defer arena.deinit();
        try std.testing.expectError(error.UnterminatedTag, template.parse(source, arena.allocator()));
    }
}
