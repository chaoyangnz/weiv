const std = @import("std");
const html_entities = @import("html_entities.zig");

pub fn emitString(value: []const u8, out: *std.ArrayList(u8), allocator: std.mem.Allocator) !void {
    try out.append(allocator, '"');
    for (value) |ch| {
        switch (ch) {
            '\\' => try out.appendSlice(allocator, "\\\\"),
            '"' => try out.appendSlice(allocator, "\\\""),
            '\n' => try out.appendSlice(allocator, "\\n"),
            '\r' => try out.appendSlice(allocator, "\\r"),
            '\t' => try out.appendSlice(allocator, "\\t"),
            else => try out.append(allocator, ch),
        }
    }
    try out.append(allocator, '"');
}

pub fn emitHtmlString(value: []const u8, out: *std.ArrayList(u8), allocator: std.mem.Allocator) !void {
    var decoded = std.ArrayList(u8).empty;
    defer decoded.deinit(allocator);
    var cursor: usize = 0;
    while (cursor < value.len) {
        if (value[cursor] == '&') {
            if (std.mem.indexOfScalarPos(u8, value, cursor + 1, ';')) |end| {
                if (end - cursor <= 40) {
                    const entity = value[cursor + 1 .. end];
                    if (html_entities.decode(entity)) |decoded_entity| {
                        try decoded.appendSlice(allocator, decoded_entity);
                        cursor = end + 1;
                        continue;
                    }
                    if (decodeNumericEntity(entity)) |codepoint| {
                        var buffer: [4]u8 = undefined;
                        const size = try std.unicode.utf8Encode(codepoint, &buffer);
                        try decoded.appendSlice(allocator, buffer[0..size]);
                        cursor = end + 1;
                        continue;
                    }
                }
            }
        }
        try decoded.append(allocator, value[cursor]);
        cursor += 1;
    }
    try emitString(decoded.items, out, allocator);
}

fn decodeNumericEntity(entity: []const u8) ?u21 {
    if (entity.len < 2 or entity[0] != '#') return null;
    const hex = entity.len > 2 and (entity[1] == 'x' or entity[1] == 'X');
    const digits = entity[if (hex) @as(usize, 2) else 1..];
    if (digits.len == 0) return null;
    const codepoint = std.fmt.parseInt(u21, digits, if (hex) 16 else 10) catch return null;
    if (codepoint == 0 or codepoint > 0x10FFFF or (codepoint >= 0xD800 and codepoint <= 0xDFFF)) return 0xFFFD;
    return codepoint;
}

pub fn refVarName(ref_id: usize, allocator: std.mem.Allocator) ![]u8 {
    return try std.fmt.allocPrint(allocator, "__ref_{d}", .{ref_id});
}

pub fn writeIndent(indent: usize, out: *std.ArrayList(u8), allocator: std.mem.Allocator) !void {
    var i: usize = 0;
    while (i < indent) : (i += 1) {
        try out.appendSlice(allocator, "  ");
    }
}
