// zig test --dep parser -Mroot=cyna-port/reference/template_normalize.zig -Mparser=src/compiler/parser/index.zig
const std = @import("std");
const parser = @import("parser");
const allocator = std.testing.allocator;
const equal = std.testing.expectEqual;
const text = std.testing.expectEqualStrings;

test "if consumes adjacent else but retains only the if span" {
    var raw = try parser.parseTemplate("<a #if=\"x\"/> \n <b #else/><hr>", allocator);
    defer raw.deinit(allocator);
    var output = try parser.normalizeTemplate(&raw, allocator);
    defer output.deinit(allocator);
    try equal(@as(usize, 2), output.nodes.len);
    const branch = output.nodes[0].conditional;
    try text("x", branch.condition);
    try equal(@as(usize, 1), branch.consequent.len);
    try equal(@as(usize, 1), branch.alternate.len);
    try equal(raw.nodes[0].element.span.end, branch.span.end);
    try equal(@as(usize, 0), branch.consequent[0].element.directives.len);
    try equal(@as(usize, 0), branch.alternate[0].element.directives.len);
}

test "if without else has empty alternate and preserves its next sibling" {
    var raw = try parser.parseTemplate("<a #if=\"x\"/><hr>", allocator);
    defer raw.deinit(allocator);
    var output = try parser.normalizeTemplate(&raw, allocator);
    defer output.deinit(allocator);
    try equal(@as(usize, 2), output.nodes.len);
    try equal(@as(usize, 0), output.nodes[0].conditional.alternate.len);
}

test "if overrides for and for overrides orphan else" {
    var raw = try parser.parseTemplate("<a #for=\"item in items\" #if=\"x\"/><b #else #for=\"item in items\"/>", allocator);
    defer raw.deinit(allocator);
    var output = try parser.normalizeTemplate(&raw, allocator);
    defer output.deinit(allocator);
    // b is consumed as an else branch, not separately normalized as a loop.
    try equal(@as(usize, 1), output.nodes.len);
    try equal(@as(usize, 0), output.nodes[0].conditional.consequent[0].element.directives.len);
    try equal(@as(usize, 0), output.nodes[0].conditional.alternate[0].element.directives.len);
    var loop_raw = try parser.parseTemplate("<p #else #for=\"item in items\"/>", allocator);
    defer loop_raw.deinit(allocator);
    var loop_out = try parser.normalizeTemplate(&loop_raw, allocator);
    defer loop_out.deinit(allocator);
    try text("item", loop_out.nodes[0].for_loop.item_name);
}

test "repeated structural directives select first expressions" {
    var raw = try parser.parseTemplate("<a #if=\"first\" #if=\"second\"/><b #for=\"one in left\" #for=\"two in right\"/>", allocator);
    defer raw.deinit(allocator);
    var output = try parser.normalizeTemplate(&raw, allocator);
    defer output.deinit(allocator);
    try text("first", output.nodes[0].conditional.condition);
    try text("one", output.nodes[1].for_loop.item_name);
    try text("left", output.nodes[1].for_loop.iterable_expr);
}

test "branch elements strip all structural directives but retain runtime order" {
    var raw = try parser.parseTemplate("<a #if=\"x\" @click=\"go\" :value=\"model\" slot:head/><b #else #if=\"y\" #for=\"item in items\" on:click=\"old\"/>", allocator);
    defer raw.deinit(allocator);
    var output = try parser.normalizeTemplate(&raw, allocator);
    defer output.deinit(allocator);
    const yes = output.nodes[0].conditional.consequent[0].element;
    const no = output.nodes[0].conditional.alternate[0].element;
    try equal(@as(usize, 3), yes.directives.len);
    try text("click", yes.directives[0].event.event_name);
    try text("value", yes.directives[1].bind.target_name);
    try text("head", yes.directives[2].slot_assign.slot_name);
    try equal(@as(usize, 1), no.directives.len);
    try std.testing.expect(no.directives[0].event.deprecated_syntax);
}

test "nested loop and slot fallback normalize independently" {
    var raw = try parser.parseTemplate("<slot name=\"head\"><li #for=\"item in items\"><a #if=\"item.ok\"/><b #else/></li></slot>", allocator);
    defer raw.deinit(allocator);
    var output = try parser.normalizeTemplate(&raw, allocator);
    defer output.deinit(allocator);
    const outlet = output.nodes[0].slot_outlet;
    try text("head", outlet.name.?);
    const loop = outlet.fallback_children[0].for_loop;
    try text("items", loop.iterable_expr);
    try equal(@as(usize, 1), loop.body[0].element.children[0].conditional.alternate.len);
}

test "text interpolation and parent boundaries prevent else pairing" {
    const cases = [_][]const u8{
        "<a #if=\"x\"/>text<b #else/>",
        "<a #if=\"x\"/>{{value}}<b #else/>",
        "<div><a #if=\"x\"/></div><b #else/>",
        "<slot><a #else/></slot>",
        "<a #else/>",
        "<a #if=\"x\"/><b #else/><c #else/>",
        "<a #if=\"x\"/><b #else><c #else/></b>",
    };
    for (cases) |source| {
        var arena = std.heap.ArenaAllocator.init(allocator);
        defer arena.deinit();
        const raw = try parser.parseTemplate(source, arena.allocator());
        try std.testing.expectError(error.UnexpectedElse, parser.normalizeTemplate(&raw, arena.allocator()));
    }
}
