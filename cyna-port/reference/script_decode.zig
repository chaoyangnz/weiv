// Included by tools/test-cyna-script-facts.py's repository-root Zig oracle.
const std = @import("std");
const decoder = @import("../../src/compiler/sema/decode_script_facts.zig");
const allocator = std.testing.allocator;
const empty = "{\"ok\":true,\"source_path\":\"fixture.ts\",\"transpiled_code\":\"code\",\"props\":null,\"imports\":[],\"bindings\":[],\"state_analysis\":null,\"diagnostics\":[]}";

fn check_error(expected: anyerror, payload: []const u8) !void {
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    try std.testing.expectError(expected, decoder.decode(payload, arena.allocator()));
}

test "script schema nullable members remain required" {
    try check_error(error.MissingField, "{}");
    try check_error(error.MissingField, "{\"ok\":true,\"source_path\":\"x\",\"transpiled_code\":\"\",\"imports\":[],\"bindings\":[],\"state_analysis\":null,\"diagnostics\":[]}");
    try check_error(error.MissingField, "{\"ok\":true,\"source_path\":\"x\",\"transpiled_code\":\"\",\"props\":null,\"imports\":[],\"bindings\":[],\"diagnostics\":[]}");
}

test "script schema null state means empty state and code stays separate" {
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const result = try decoder.decode(empty, arena.allocator());
    try std.testing.expect(result.facts.props == null);
    try std.testing.expectEqualStrings("code", result.transpiled_code);
    try std.testing.expectEqual(@as(usize, 0), result.facts.state_facts.helpers.len);
    try std.testing.expectEqual(@as(usize, 0), result.facts.state_facts.mutations.len);
    try std.testing.expectEqual(@as(usize, 0), result.facts.state_facts.aliases.len);
    try std.testing.expectEqual(@as(usize, 0), result.facts.state_facts.callback_registrations.len);
}

test "script schema unknown keys are ignored and state arrays default" {
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const payload = "{\"future\":{},\"ok\":true,\"source_path\":\"x\",\"transpiled_code\":\"\",\"props\":null,\"imports\":[],\"bindings\":[],\"state_analysis\":{\"future\":[]},\"diagnostics\":[]}";
    const result = try decoder.decode(payload, arena.allocator());
    try std.testing.expectEqual(@as(usize, 0), result.facts.state_facts.helpers.len);
}

test "script schema rejects collection shapes and missing record fields" {
    try check_error(error.UnexpectedToken, "{\"ok\":true,\"source_path\":\"x\",\"transpiled_code\":\"\",\"props\":null,\"imports\":{},\"bindings\":[],\"state_analysis\":null,\"diagnostics\":[]}");
    try check_error(error.MissingField, "{\"ok\":true,\"source_path\":\"x\",\"transpiled_code\":\"\",\"props\":null,\"imports\":[],\"bindings\":[{\"name\":\"x\"}],\"state_analysis\":null,\"diagnostics\":[]}");
}

test "Zig numeric coercions are intentionally excluded by the Cyna schema" {
    for ([_][]const u8{ "\"1\"", "1.0", "1e0" }) |number| {
        var arena = std.heap.ArenaAllocator.init(allocator);
        defer arena.deinit();
        const payload = try std.fmt.allocPrint(arena.allocator(), "{{\"ok\":true,\"source_path\":\"x\",\"transpiled_code\":\"\",\"props\":null,\"imports\":[],\"bindings\":[{{\"name\":\"x\",\"kind\":\"mutable\",\"exported\":false,\"template_visible\":true,\"callable\":false,\"type_annotation\":null,\"span_start\":{s},\"span_end\":2}}],\"state_analysis\":null,\"diagnostics\":[]}}", .{number});
        const result = try decoder.decode(payload, arena.allocator());
        try std.testing.expectEqual(@as(usize, 1), result.facts.bindings[0].span_start);
    }
}

test "Zig accepts inverted ranges that Cyna rejects explicitly" {
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const payload = "{\"ok\":true,\"source_path\":\"x\",\"transpiled_code\":\"\",\"props\":null,\"imports\":[],\"bindings\":[{\"name\":\"x\",\"kind\":\"mutable\",\"exported\":false,\"template_visible\":true,\"callable\":false,\"type_annotation\":null,\"span_start\":9,\"span_end\":1}],\"state_analysis\":null,\"diagnostics\":[]}";
    const result = try decoder.decode(payload, arena.allocator());
    try std.testing.expectEqual(@as(usize, 9), result.facts.bindings[0].span_start);
    try std.testing.expectEqual(@as(usize, 1), result.facts.bindings[0].span_end);
}
