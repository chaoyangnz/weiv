// Optional reference contracts; everyday regression tests remain native Cyna.
// zig test --dep parser -Mroot=cyna-port/reference/template_dynamic.zig -Mparser=src/compiler/parser/index.zig
const std = @import("std");
const parser = @import("parser");
const template = parser.template;
const allocator = std.testing.allocator;
const equal = std.testing.expectEqual;
const text = std.testing.expectEqualStrings;
const expect = std.testing.expect;

fn parse(source: []const u8) !template.Document {
    return template.parse(source, allocator);
}

fn error_cases(expected: anyerror, sources: []const []const u8) !void {
    for (sources) |source| {
        var arena = std.heap.ArenaAllocator.init(allocator);
        defer arena.deinit();
        try std.testing.expectError(expected, template.parse(source, arena.allocator()));
    }
}

test "interpolation delimiting trimming and adjacent text" {
    var doc = try parse("<p>A{{  x + 1  }}B{{y}}</p>");
    defer doc.deinit(allocator);
    const children = doc.nodes[0].element.children;
    try equal(@as(usize, 4), children.len);
    try equal(@as(usize, 4), children[1].interpolation.span.start);
    try equal(@as(usize, 17), children[1].interpolation.span.end);
    try text("x + 1", children[1].interpolation.expression);
    try text("y", children[3].interpolation.expression);
    var empty = try parse("{{}}{{ \t }}{{ café 🌱 }}");
    defer empty.deinit(allocator);
    try text("", empty.nodes[0].interpolation.expression);
    try text("", empty.nodes[1].interpolation.expression);
    try text("café 🌱", empty.nodes[2].interpolation.expression);
    var quote = try parse("{{ \"}}\" }}");
    defer quote.deinit(allocator);
    try equal(@as(usize, 2), quote.nodes.len);
    try text("\"", quote.nodes[0].interpolation.expression);
    try equal(@as(usize, 6), quote.nodes[0].interpolation.span.end);
}

test "unterminated interpolation takes precedence over missing close" {
    try error_cases(error.UnterminatedInterpolation, &.{ "{{", "<p>{{x</p>", "<p>{{ x }" });
}

test "structural directive split preserves order and raw expressions" {
    var doc = try parse("<p class=\"x\" #if=\" ready \" #for=\" item in items \" #else/>");
    defer doc.deinit(allocator);
    const element = doc.nodes[0].element;
    try equal(@as(usize, 1), element.attributes.len);
    try equal(@as(usize, 3), element.directives.len);
    try text(" ready ", element.directives[0].if_expr.expression);
    try text("item", element.directives[1].for_expr.item_name);
    try text("items", element.directives[1].for_expr.iterable_expr);
    try expect(element.directives[2] == .else_branch);
    var first = try parse("<p #for=\"item in left in right\"/>");
    defer first.deinit(allocator);
    try text("left in right", first.nodes[0].element.directives[0].for_expr.iterable_expr);
}

test "canonical and legacy handlers preserve target and metadata" {
    var doc = try parse("<p @click=\"go()\" :value=\"model\"/>");
    defer doc.deinit(allocator);
    const directives = doc.nodes[0].element.directives;
    try text("click", directives[0].event.event_name);
    try text("go()", directives[0].event.expression);
    try expect(!directives[0].event.deprecated_syntax);
    try text("value", directives[1].bind.target_name);
    try text("model", directives[1].bind.expression);
    try expect(!directives[1].bind.deprecated_syntax);
    var legacy = try parse("<p on:=\"\" bind:=\"\"/>");
    defer legacy.deinit(allocator);
    const old = legacy.nodes[0].element.directives;
    try expect(old[0].event.deprecated_syntax);
    try text("", old[0].event.event_name);
    try expect(old[1].bind.deprecated_syntax);
    try text("", old[1].bind.target_name);
}

test "unknown hash names remain attributes and named projection becomes a directive" {
    var doc = try parse("<Header slot:title #custom=\"value\"/>");
    defer doc.deinit(allocator);
    try text("title", doc.nodes[0].element.directives[0].slot_assign.slot_name);
    try text("#custom", doc.nodes[0].element.attributes[0].name);
}

test "invalid directives preserve reference diagnostics" {
    try error_cases(error.InvalidDirective, &.{
        "<p #if/>",                      "<p #else=\"x\"/>",        "<p #for/>",              "<p @click/>",  "<p :value/>",
        "<p on:click/>",                 "<p bind:value/>",         "<p @=\"x\"/>",           "<p :=\"x\"/>", "<p #for=\"items\"/>",
        "<p #for=\"item\tin\titems\"/>", "<p #for=\" in items\"/>", "<p #for=\"item in \"/>", "<p slot:/>",   "<p slot:title=\"x\"/>",
    });
}

test "default slot fallback spans and siblings" {
    var doc = try parse("<slot><b>fallback</b>{{other}}</slot><p/>");
    defer doc.deinit(allocator);
    try equal(@as(usize, 2), doc.nodes.len);
    const outlet = doc.nodes[0].slot_outlet;
    try expect(outlet.name == null);
    try equal(@as(usize, 37), outlet.span.end);
    try equal(@as(usize, 2), outlet.fallback_children.len);
    try text("fallback", outlet.fallback_children[0].element.children[0].text.content);
    try text("other", outlet.fallback_children[1].interpolation.expression);
}

test "named and explicitly empty slot names" {
    var doc = try parse("<slot name=\"header\"/>");
    defer doc.deinit(allocator);
    try text("header", doc.nodes[0].slot_outlet.name.?);
    var empty = try parse("<slot name=\"\"/>");
    defer empty.deinit(allocator);
    try text("", empty.nodes[0].slot_outlet.name.?);
}

test "slot constraints and error precedence" {
    try error_cases(error.InvalidSlotOutlet, &.{
        "<slot name/>",                 "<slot class=\"x\"/>", "<slot name=\"x\" name=\"y\"/>",
        "<slot name=\"\" name=\"x\"/>", "<slot #if=\"yes\"/>", "<slot slot:header/>",
    });
    try error_cases(error.MismatchedCloseTag, &.{ "<slot class=\"x\"><b></slot>", "<slot class=\"x\">" });
    try error_cases(error.InvalidDirective, &.{"<slot #if></slot>"});
    try error_cases(error.UnterminatedInterpolation, &.{"<slot @click=\"go\">{{"});
}
