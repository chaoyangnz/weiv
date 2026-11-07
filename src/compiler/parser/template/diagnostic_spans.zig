const ast = @import("ast.zig");
const directives = @import("directives.zig");
const sfc = @import("../sfc.zig");

// Locate parser normalization failures without constructing compiler diagnostics.
pub fn findFirstInvalidNormalizeSpan(
    nodes: []const ast.Node,
    err: anyerror,
) ?sfc.Span {
    return findInvalidNormalizeSpanInNodes(nodes, err);
}

fn findInvalidNormalizeSpanInNodes(nodes: []const ast.Node, err: anyerror) ?sfc.Span {
    if (err != error.UnexpectedElse) return null;

    var i: usize = 0;
    while (i < nodes.len) : (i += 1) {
        switch (nodes[i]) {
            .element => |element| {
                if (hasElseDirective(element.directives) and !previousSiblingHasIf(nodes, i)) {
                    return element.span;
                }
                if (findInvalidNormalizeSpanInNodes(element.children, err)) |span| return span;
            },
            .slot_outlet => |slot_outlet| {
                if (findInvalidNormalizeSpanInNodes(slot_outlet.fallback_children, err)) |span| return span;
            },
            .text, .interpolation => {},
        }
    }

    return null;
}

fn hasElseDirective(input: []const directives.Directive) bool {
    for (input) |directive| {
        switch (directive) {
            .else_branch => return true,
            else => {},
        }
    }
    return false;
}

fn previousSiblingHasIf(nodes: []const ast.Node, index: usize) bool {
    if (index == 0) return false;
    switch (nodes[index - 1]) {
        .element => |element| {
            for (element.directives) |directive| {
                switch (directive) {
                    .if_expr => return true,
                    else => {},
                }
            }
            return false;
        },
        else => return false,
    }
}
