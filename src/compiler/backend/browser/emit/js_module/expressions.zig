const std = @import("std");
const script_backend = @import("../../../../../ffi/script_backend.zig");

pub fn isCellExpression(source: []const u8) bool {
    return std.mem.startsWith(u8, source, "\x00weiv:");
}

fn isPropertyAccessExpr(expr: []const u8, ident_start: usize) bool {
    var cursor = ident_start;
    while (cursor > 0) {
        cursor -= 1;
        if (isWhitespace(expr[cursor])) continue;
        return expr[cursor] == '.' and !(cursor >= 2 and std.mem.eql(u8, expr[cursor - 2 .. cursor + 1], "..."));
    }
    return false;
}

fn isKeyword(ident: []const u8) bool {
    const keywords = [_][]const u8{
        "true",
        "false",
        "null",
        "undefined",
        "typeof",
        "instanceof",
        "return",
        "new",
        "await",
    };
    for (keywords) |keyword| {
        if (std.mem.eql(u8, ident, keyword)) return true;
    }
    return false;
}

fn isTemplateGlobal(ident: []const u8) bool {
    const globals = [_][]const u8{
        "Math",     "String",             "Number",             "Boolean", "BigInt",   "Array",      "Object",
        "JSON",     "Date",               "Intl",               "RegExp",  "parseInt", "parseFloat", "isNaN",
        "isFinite", "encodeURIComponent", "decodeURIComponent",
    };
    for (globals) |global| {
        if (std.mem.eql(u8, ident, global)) return true;
    }
    return false;
}

fn appendScopedRoot(ident: []const u8, scope_expr: []const u8, out: *std.ArrayList(u8), allocator: std.mem.Allocator) !void {
    if (std.mem.eql(u8, ident, "globalThis")) {
        try out.appendSlice(allocator, ident);
    } else if (isTemplateGlobal(ident)) {
        try out.print(allocator, "({s}.{s} ?? globalThis.{s})", .{ scope_expr, ident, ident });
    } else {
        try out.print(allocator, "{s}.{s}", .{ scope_expr, ident });
    }
}

fn isIdentStart(ch: u8) bool {
    return std.ascii.isAlphabetic(ch) or ch == '_' or ch == '$';
}

fn isIdentContinue(ch: u8) bool {
    return isIdentStart(ch) or std.ascii.isDigit(ch);
}

fn isWhitespace(ch: u8) bool {
    return ch == ' ' or ch == '\n' or ch == '\r' or ch == '\t';
}

pub fn emitResolvedExpression(
    expression: []const u8,
    scope_expr: []const u8,
    bindings_json: []const u8,
    out: *std.ArrayList(u8),
    allocator: std.mem.Allocator,
) anyerror!void {
    const trimmed = std.mem.trim(u8, expression, &std.ascii.whitespace);
    if (trimmed.len == 0) {
        try out.appendSlice(allocator, "undefined");
        return;
    }
    if (std.mem.startsWith(u8, trimmed, "\x00weiv:")) {
        var parts = std.mem.splitScalar(u8, trimmed[6..], ':');
        const id = parts.next() orelse return error.InvalidCellExpression;
        _ = std.fmt.parseInt(usize, id, 10) catch return error.InvalidCellExpression;
        const argument = parts.next() orelse return error.InvalidCellExpression;
        if (parts.next() != null or (!std.mem.eql(u8, argument, "render") and !std.mem.eql(u8, argument, "event") and !std.mem.eql(u8, argument, "payload"))) return error.InvalidCellExpression;
        try out.print(allocator, "((__weiv_context) => __weiv_context.__weiv_eval[{s}](__weiv_context", .{id});
        if (!std.mem.eql(u8, argument, "render")) try out.print(allocator, ", {s}", .{argument});
        try out.print(allocator, "))({s})", .{scope_expr});
        return;
    }

    if (isLiteralExpression(trimmed)) {
        try out.appendSlice(allocator, trimmed);
        return;
    }

    if (try tryRewriteTemplateLiteral(trimmed, scope_expr, bindings_json, out, allocator)) {
        return;
    }

    if (isSimpleAccessExpression(trimmed)) {
        const root_end = std.mem.indexOfScalar(u8, trimmed, '.') orelse trimmed.len;
        try appendScopedRoot(trimmed[0..root_end], scope_expr, out, allocator);
        try out.appendSlice(allocator, trimmed[root_end..]);
        return;
    }

    // Object shorthand, callback locals and spread operands need lexical AST
    // rewriting; token scanning cannot distinguish all of their roles.
    if ((std.mem.indexOfScalar(u8, trimmed, '{') != null or std.mem.indexOf(u8, trimmed, "...") != null or std.mem.indexOf(u8, trimmed, "=>") != null) and bindings_json.len > 0) {
        if (script_backend.rewriteExpression(trimmed, bindings_json, scope_expr, allocator)) |rewritten| {
            defer allocator.free(rewritten);
            try out.appendSlice(allocator, rewritten);
            return;
        } else |_| {}
    }

    if (try tryRewriteScopedCallExpression(trimmed, scope_expr, out, allocator)) {
        return;
    }

    if (try tryRewriteScopedExpression(trimmed, scope_expr, out, allocator)) {
        return;
    }

    if (bindings_json.len > 0) {
        if (script_backend.rewriteExpression(trimmed, bindings_json, scope_expr, allocator)) |rewritten| {
            defer allocator.free(rewritten);
            try out.appendSlice(allocator, rewritten);
            return;
        } else |_| {}
    }

    return error.UnsupportedTemplateExpression;
}

fn tryRewriteTemplateLiteral(
    expression: []const u8,
    scope_expr: []const u8,
    bindings_json: []const u8,
    out: *std.ArrayList(u8),
    allocator: std.mem.Allocator,
) anyerror!bool {
    if (expression.len < 2 or expression[0] != '`' or expression[expression.len - 1] != '`') return false;
    var rewritten = std.ArrayList(u8).empty;
    defer rewritten.deinit(allocator);
    var cursor: usize = 0;
    while (cursor < expression.len) {
        if (expression[cursor] == '\\' and cursor + 1 < expression.len) {
            try rewritten.appendSlice(allocator, expression[cursor .. cursor + 2]);
            cursor += 2;
            continue;
        }
        if (cursor + 1 < expression.len and expression[cursor] == '$' and expression[cursor + 1] == '{') {
            const start = cursor + 2;
            var end = start;
            var depth: usize = 1;
            while (end < expression.len and depth > 0) : (end += 1) {
                if (expression[end] == '\'' or expression[end] == '"') {
                    end = (scanQuotedString(expression, end) orelse return false);
                    continue;
                }
                if (expression[end] == '{') depth += 1;
                if (expression[end] == '}') depth -= 1;
            }
            if (depth != 0) return false;
            const inner = expression[start .. end - 1];
            try rewritten.appendSlice(allocator, "${");
            try emitResolvedExpression(inner, scope_expr, bindings_json, &rewritten, allocator);
            try rewritten.append(allocator, '}');
            cursor = end;
            continue;
        }
        try rewritten.append(allocator, expression[cursor]);
        cursor += 1;
    }
    try out.appendSlice(allocator, rewritten.items);
    return true;
}

fn isLiteralExpression(expression: []const u8) bool {
    if (expression.len == 0) return false;
    if ((expression[0] == '\'' and expression[expression.len - 1] == '\'') or
        (expression[0] == '"' and expression[expression.len - 1] == '"')) return expression.len >= 2;

    if (std.mem.eql(u8, expression, "true") or
        std.mem.eql(u8, expression, "false") or
        std.mem.eql(u8, expression, "null") or
        std.mem.eql(u8, expression, "undefined")) return true;

    var seen_digit = false;
    var seen_dot = false;
    for (expression, 0..) |ch, idx| {
        if (idx == 0 and (ch == '+' or ch == '-')) continue;
        if (std.ascii.isDigit(ch)) {
            seen_digit = true;
            continue;
        }
        if (ch == '.' and !seen_dot) {
            seen_dot = true;
            continue;
        }
        return false;
    }
    return seen_digit;
}

fn isSimpleAccessExpression(expression: []const u8) bool {
    var cursor: usize = 0;
    if (!consumeIdentifier(expression, &cursor)) return false;
    while (cursor < expression.len) {
        if (expression[cursor] != '.') return false;
        cursor += 1;
        if (!consumeIdentifier(expression, &cursor)) return false;
    }
    return true;
}

fn consumeIdentifier(expression: []const u8, cursor: *usize) bool {
    if (cursor.* >= expression.len or !isIdentStart(expression[cursor.*])) return false;
    cursor.* += 1;
    while (cursor.* < expression.len and isIdentContinue(expression[cursor.*])) cursor.* += 1;
    return true;
}

fn tryRewriteScopedExpression(
    expression: []const u8,
    scope_expr: []const u8,
    out: *std.ArrayList(u8),
    allocator: std.mem.Allocator,
) !bool {
    return try tryRewriteScopedExpressionWithLocals(expression, scope_expr, &.{}, out, allocator);
}

fn tryRewriteScopedExpressionWithLocals(
    expression: []const u8,
    scope_expr: []const u8,
    locals: []const []const u8,
    out: *std.ArrayList(u8),
    allocator: std.mem.Allocator,
) !bool {
    var rewritten = std.ArrayList(u8).empty;
    defer rewritten.deinit(allocator);

    var cursor: usize = 0;
    while (cursor < expression.len) {
        const ch = expression[cursor];
        if (isWhitespace(ch)) {
            try rewritten.append(allocator, ch);
            cursor += 1;
            continue;
        }

        if (ch == '\'' or ch == '"') {
            const end = scanQuotedString(expression, cursor) orelse return false;
            try rewritten.appendSlice(allocator, expression[cursor .. end + 1]);
            cursor = end + 1;
            continue;
        }

        if (isIdentStart(ch)) {
            const start = cursor;
            cursor += 1;
            while (cursor < expression.len and isIdentContinue(expression[cursor])) cursor += 1;
            const ident = expression[start..cursor];

            if (isKeyword(ident)) {
                try rewritten.appendSlice(allocator, ident);
                continue;
            }

            if (containsName(locals, ident)) {
                try rewritten.appendSlice(allocator, ident);
                continue;
            }

            if (isPropertyAccessExpr(expression, start)) {
                try rewritten.appendSlice(allocator, ident);
                continue;
            }

            try appendScopedRoot(ident, scope_expr, &rewritten, allocator);
            continue;
        }

        if (std.ascii.isDigit(ch)) {
            const start = cursor;
            cursor += 1;
            while (cursor < expression.len and (std.ascii.isDigit(expression[cursor]) or expression[cursor] == '.')) cursor += 1;
            try rewritten.appendSlice(allocator, expression[start..cursor]);
            continue;
        }

        if (isSupportedExpressionPunctuation(ch)) {
            try rewritten.append(allocator, ch);
            cursor += 1;
            continue;
        }

        return false;
    }

    try out.appendSlice(allocator, rewritten.items);
    return true;
}

fn tryRewriteScopedCallExpression(
    expression: []const u8,
    scope_expr: []const u8,
    out: *std.ArrayList(u8),
    allocator: std.mem.Allocator,
) !bool {
    const open_paren = std.mem.indexOfScalar(u8, expression, '(') orelse return false;
    const callee = std.mem.trimEnd(u8, expression[0..open_paren], &std.ascii.whitespace);
    if (callee.len == 0 or !isSimpleAccessExpression(callee)) return false;

    const close_paren = findMatchingParen(expression, open_paren) orelse return false;
    const suffix = std.mem.trim(u8, expression[close_paren + 1 ..], &std.ascii.whitespace);
    if (suffix.len != 0 and !isSimpleCallSuffixExpression(suffix)) return false;

    var rewritten = std.ArrayList(u8).empty;
    defer rewritten.deinit(allocator);

    const root_end = std.mem.indexOfScalar(u8, callee, '.') orelse callee.len;
    try appendScopedRoot(callee[0..root_end], scope_expr, &rewritten, allocator);
    try rewritten.appendSlice(allocator, callee[root_end..]);
    try rewritten.append(allocator, '(');

    const args_source = expression[open_paren + 1 .. close_paren];
    var args = std.ArrayList([]const u8).empty;
    defer args.deinit(allocator);
    try splitCallArguments(args_source, &args, allocator);

    for (args.items, 0..) |arg, idx| {
        if (idx > 0) try rewritten.appendSlice(allocator, ", ");
        const trimmed_arg = std.mem.trim(u8, arg, &std.ascii.whitespace);
        if (trimmed_arg.len == 0) continue;
        if (try tryRewriteArrowCallbackExpression(trimmed_arg, scope_expr, &rewritten, allocator)) continue;
        if (!try tryRewriteScopedExpression(trimmed_arg, scope_expr, &rewritten, allocator)) return false;
    }

    try rewritten.append(allocator, ')');
    if (suffix.len != 0 and !try appendScopedCallSuffix(suffix, scope_expr, &rewritten, allocator)) return false;
    try out.appendSlice(allocator, rewritten.items);
    return true;
}

fn tryRewriteArrowCallbackExpression(
    expression: []const u8,
    scope_expr: []const u8,
    out: *std.ArrayList(u8),
    allocator: std.mem.Allocator,
) !bool {
    const arrow = std.mem.indexOf(u8, expression, "=>") orelse return false;
    const params_expr = std.mem.trim(u8, expression[0..arrow], &std.ascii.whitespace);
    const raw_body_expr = std.mem.trim(u8, expression[arrow + 2 ..], &std.ascii.whitespace);
    const body_expr = extractArrowCallbackReturnExpression(raw_body_expr) orelse return false;
    if (params_expr.len == 0 or body_expr.len == 0) return false;

    const param = parseArrowCallbackParam(params_expr) orelse return false;
    const locals = [_][]const u8{param};

    try out.appendSlice(allocator, params_expr);
    if (raw_body_expr.len > 0 and raw_body_expr[0] == '{') {
        try out.appendSlice(allocator, " => { return ");
        if (!try tryRewriteScopedExpressionWithLocals(body_expr, scope_expr, &locals, out, allocator)) return false;
        try out.appendSlice(allocator, "; }");
        return true;
    }

    try out.appendSlice(allocator, " => ");
    if (!try tryRewriteScopedExpressionWithLocals(body_expr, scope_expr, &locals, out, allocator)) return false;
    return true;
}

fn parseArrowCallbackParam(params_expr: []const u8) ?[]const u8 {
    const trimmed = std.mem.trim(u8, params_expr, &std.ascii.whitespace);
    if (trimmed.len == 0) return null;
    if (trimmed[0] == '(') {
        if (trimmed[trimmed.len - 1] != ')') return null;
        const inner = std.mem.trim(u8, trimmed[1 .. trimmed.len - 1], &std.ascii.whitespace);
        if (inner.len == 0 or !isSimpleAccessExpression(inner)) return null;
        return inner;
    }
    if (!isSimpleAccessExpression(trimmed)) return null;
    return trimmed;
}

fn extractArrowCallbackReturnExpression(body_expr: []const u8) ?[]const u8 {
    const trimmed = std.mem.trim(u8, body_expr, &std.ascii.whitespace);
    if (trimmed.len == 0) return null;
    if (trimmed[0] != '{') return trimmed;
    if (trimmed[trimmed.len - 1] != '}') return null;

    const inner = std.mem.trim(u8, trimmed[1 .. trimmed.len - 1], &std.ascii.whitespace);
    if (!std.mem.startsWith(u8, inner, "return")) return null;

    const return_expr = std.mem.trim(u8, inner["return".len..], &std.ascii.whitespace);
    if (return_expr.len == 0) return null;
    if (return_expr[return_expr.len - 1] != ';') return null;

    const expr = std.mem.trim(u8, return_expr[0 .. return_expr.len - 1], &std.ascii.whitespace);
    if (expr.len == 0) return null;
    return expr;
}

fn isSimpleCallSuffixExpression(expression: []const u8) bool {
    var cursor: usize = 0;
    while (cursor < expression.len) {
        if (expression[cursor] != '.') return false;
        cursor += 1;
        if (!consumeIdentifier(expression, &cursor)) return false;
        if (cursor < expression.len and expression[cursor] == '(') {
            const end = findMatchingParen(expression, cursor) orelse return false;
            cursor = end + 1;
        }
    }
    return true;
}

fn appendScopedCallSuffix(
    suffix: []const u8,
    scope_expr: []const u8,
    out: *std.ArrayList(u8),
    allocator: std.mem.Allocator,
) !bool {
    var cursor: usize = 0;
    while (cursor < suffix.len) {
        if (suffix[cursor] != '.') return false;
        const start = cursor;
        cursor += 1;
        if (!consumeIdentifier(suffix, &cursor)) return false;
        try out.appendSlice(allocator, suffix[start..cursor]);
        if (cursor >= suffix.len or suffix[cursor] != '(') continue;
        const close = findMatchingParen(suffix, cursor) orelse return false;
        try out.append(allocator, '(');
        var args = std.ArrayList([]const u8).empty;
        defer args.deinit(allocator);
        try splitCallArguments(suffix[cursor + 1 .. close], &args, allocator);
        for (args.items, 0..) |arg, idx| {
            const trimmed = std.mem.trim(u8, arg, &std.ascii.whitespace);
            if (trimmed.len == 0) continue;
            if (idx > 0) try out.appendSlice(allocator, ", ");
            if (try tryRewriteArrowCallbackExpression(trimmed, scope_expr, out, allocator)) continue;
            if (!try tryRewriteScopedExpression(trimmed, scope_expr, out, allocator)) return false;
        }
        try out.append(allocator, ')');
        cursor = close + 1;
    }
    return true;
}

fn containsName(names: []const []const u8, needle: []const u8) bool {
    for (names) |name| {
        if (std.mem.eql(u8, name, needle)) return true;
    }
    return false;
}

fn splitCallArguments(
    source: []const u8,
    out: *std.ArrayList([]const u8),
    allocator: std.mem.Allocator,
) !void {
    var start: usize = 0;
    var depth_paren: usize = 0;
    var depth_bracket: usize = 0;
    var depth_brace: usize = 0;
    var cursor: usize = 0;
    while (cursor < source.len) : (cursor += 1) {
        const ch = source[cursor];
        if (ch == '\'' or ch == '"') {
            const end = scanQuotedString(source, cursor) orelse return error.InvalidCallArgumentString;
            cursor = end;
            continue;
        }
        switch (ch) {
            '(' => depth_paren += 1,
            ')' => {
                if (depth_paren > 0) depth_paren -= 1;
            },
            '[' => depth_bracket += 1,
            ']' => {
                if (depth_bracket > 0) depth_bracket -= 1;
            },
            '{' => depth_brace += 1,
            '}' => {
                if (depth_brace > 0) depth_brace -= 1;
            },
            ',' => {
                if (depth_paren == 0 and depth_bracket == 0 and depth_brace == 0) {
                    try out.append(allocator, source[start..cursor]);
                    start = cursor + 1;
                }
            },
            else => {},
        }
    }
    if (start <= source.len) {
        try out.append(allocator, source[start..]);
    }
}

fn findMatchingParen(source: []const u8, open_paren: usize) ?usize {
    var depth: usize = 0;
    var cursor = open_paren;
    while (cursor < source.len) : (cursor += 1) {
        const ch = source[cursor];
        if (ch == '\'' or ch == '"') {
            cursor = scanQuotedString(source, cursor) orelse return null;
            continue;
        }
        if (ch == '(') {
            depth += 1;
            continue;
        }
        if (ch == ')') {
            depth -= 1;
            if (depth == 0) return cursor;
        }
    }
    return null;
}

fn scanQuotedString(expression: []const u8, start: usize) ?usize {
    const quote = expression[start];
    var cursor = start + 1;
    while (cursor < expression.len) : (cursor += 1) {
        if (expression[cursor] == '\\') {
            cursor += 1;
            continue;
        }
        if (expression[cursor] == quote) return cursor;
    }
    return null;
}

fn isSupportedExpressionPunctuation(ch: u8) bool {
    return switch (ch) {
        '.', '(', ')', '[', ']', '?', ':', '!', '=', '>', '<', '&', '|', '+', '-', '*', '/', '%', ',' => true,
        else => false,
    };
}
