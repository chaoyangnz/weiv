const std = @import("std");

pub fn startsWith(source: []const u8, index: usize, needle: []const u8) bool {
    if (index + needle.len > source.len) return false;
    return std.mem.eql(u8, source[index .. index + needle.len], needle);
}

pub fn isWhitespaceOnly(value: []const u8) bool {
    for (value) |char| {
        if (!std.ascii.isWhitespace(char)) return false;
    }
    return true;
}

pub fn findOpenTagEnd(source: []const u8, start: usize) ?usize {
    var i = start;
    var in_quote = false;
    while (i < source.len) : (i += 1) {
        const char = source[i];
        if (char == '"') {
            in_quote = !in_quote;
            continue;
        }
        if (char == '>' and !in_quote) return i;
    }
    return null;
}
