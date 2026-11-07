const std = @import("std");
const ast = @import("ast.zig");
const attrs = @import("attributes.zig");
const scan = @import("scan.zig");
const directives = @import("directives.zig");
const interp = @import("interpolation.zig");
const sfc = @import("../sfc.zig");

pub const ParseError = error{
    OutOfMemory,
    UnexpectedCloseTag,
    UnterminatedTag,
    UnterminatedInterpolation,
    MismatchedCloseTag,
    InvalidDirective,
    InvalidSlotOutlet,
};

pub fn parse(source: []const u8, allocator: std.mem.Allocator) ParseError!ast.Document {
    var index: usize = 0;
    const nodes = try parseNodes(source, allocator, &index, null);
    return .{
        .source = source,
        .nodes = nodes,
    };
}

fn parseNodes(
    source: []const u8,
    allocator: std.mem.Allocator,
    index: *usize,
    until_tag: ?[]const u8,
) ParseError![]ast.Node {
    var list = std.ArrayList(ast.Node).empty;
    defer list.deinit(allocator);

    while (index.* < source.len) {
        if (until_tag) |tag_name| {
            if (startsWithCloseTag(source, index.*, tag_name)) break;
        }

        if (scan.startsWith(source, index.*, "{{")) {
            try list.append(allocator, try interp.parseInterpolation(source, index));
            continue;
        }

        if (source[index.*] == '<') {
            if (scan.startsWith(source, index.*, "</")) {
                if (until_tag == null) return error.UnexpectedCloseTag;
                break;
            }
            var node = try parseElement(source, allocator, index);
            errdefer node.deinit(allocator);
            try list.append(allocator, node);
            continue;
        }

        const text_node = interp.parseText(source, index);
        if (!scan.isWhitespaceOnly(text_node.text.content)) {
            try list.append(allocator, text_node);
        }
    }

    return try list.toOwnedSlice(allocator);
}

fn parseElement(source: []const u8, allocator: std.mem.Allocator, index: *usize) ParseError!ast.Node {
    const open_start = index.*;
    const gt = scan.findOpenTagEnd(source, open_start) orelse return error.UnterminatedTag;
    const open_end = gt + 1;
    const explicit_self_closing = gt > open_start and source[gt - 1] == '/';
    const raw_inner = source[open_start + 1 .. if (explicit_self_closing) gt - 1 else gt];
    const inner = std.mem.trim(u8, raw_inner, &std.ascii.whitespace);

    var parts = std.mem.tokenizeAny(u8, inner, &std.ascii.whitespace);
    const tag_name = parts.next() orelse return error.UnterminatedTag;
    const self_closing = explicit_self_closing or isHtmlVoidTag(tag_name);
    const attrs_source = std.mem.trim(u8, inner[tag_name.len..], &std.ascii.whitespace);
    const attrs_base_offset = @intFromPtr(attrs_source.ptr) - @intFromPtr(source.ptr);
    const raw_attributes = try attrs.parseAttributes(attrs_source, attrs_base_offset, allocator);
    defer allocator.free(raw_attributes);
    const split_attributes = try directives.split(raw_attributes, allocator);
    errdefer {
        allocator.free(split_attributes.attributes);
        allocator.free(split_attributes.directives);
    }

    index.* = open_end;

    var children: []ast.Node = &.{};
    if (!self_closing) {
        children = try parseNodes(source, allocator, index, tag_name);
        errdefer {
            for (children) |*child| child.deinit(allocator);
            allocator.free(children);
        }
        try consumeCloseTag(source, index, tag_name);
    }

    if (std.mem.eql(u8, tag_name, "slot")) {
        return try parseSlotOutlet(tag_name, split_attributes.attributes, split_attributes.directives, children, open_start, index.*, allocator);
    }

    return .{
        .element = .{
            .tag_name = tag_name,
            .attributes = split_attributes.attributes,
            .directives = split_attributes.directives,
            .children = children,
            .span = .{ .start = open_start, .end = index.* },
        },
    };
}

fn isHtmlVoidTag(tag_name: []const u8) bool {
    const void_tags = [_][]const u8{
        "area", "base", "br",    "col",    "embed", "hr",  "img", "input",
        "link", "meta", "param", "source", "track", "wbr",
    };
    for (void_tags) |void_tag| {
        if (std.ascii.eqlIgnoreCase(tag_name, void_tag)) return true;
    }
    return false;
}

fn parseSlotOutlet(
    tag_name: []const u8,
    attributes: []ast.Attribute,
    slot_directives: []directives.Directive,
    children: []ast.Node,
    start: usize,
    end: usize,
    allocator: std.mem.Allocator,
) ParseError!ast.Node {
    _ = tag_name;
    if (slot_directives.len != 0) return error.InvalidSlotOutlet;
    allocator.free(slot_directives);

    var slot_name: ?[]const u8 = null;
    for (attributes) |attribute| {
        if (!std.mem.eql(u8, attribute.name, "name")) return error.InvalidSlotOutlet;
        if (slot_name != null) return error.InvalidSlotOutlet;
        slot_name = attribute.value orelse return error.InvalidSlotOutlet;
    }
    allocator.free(attributes);

    return .{
        .slot_outlet = .{
            .name = slot_name,
            .fallback_children = children,
            .span = .{ .start = start, .end = end },
        },
    };
}

fn consumeCloseTag(source: []const u8, index: *usize, tag_name: []const u8) ParseError!void {
    if (!startsWithCloseTag(source, index.*, tag_name)) return error.MismatchedCloseTag;
    const gt = std.mem.indexOfScalarPos(u8, source, index.*, '>') orelse return error.UnterminatedTag;
    index.* = gt + 1;
}

fn startsWithCloseTag(source: []const u8, index: usize, tag_name: []const u8) bool {
    if (!scan.startsWith(source, index, "</")) return false;
    if (index + 2 + tag_name.len >= source.len) return false;
    if (!std.mem.eql(u8, source[index + 2 .. index + 2 + tag_name.len], tag_name)) return false;
    const next = source[index + 2 + tag_name.len];
    return next == '>' or std.ascii.isWhitespace(next);
}
