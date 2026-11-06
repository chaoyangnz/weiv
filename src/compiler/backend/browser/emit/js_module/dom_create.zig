const std = @import("std");
const browser_render_tree = @import("../../render_tree/index.zig");
const common = @import("common.zig");
const expression_codegen = @import("expression_codegen.zig");
const component_codegen = @import("component_codegen.zig");
const slot_codegen = @import("slot_codegen.zig");

pub fn emitCreateFunction(
    render_tree: browser_render_tree.Document,
    scope_id: []const u8,
    out: *std.ArrayList(u8),
    allocator: std.mem.Allocator,
) !void {
    try out.appendSlice(allocator,
        \\function createDom(instance) {
        \\  const fragment = document.createDocumentFragment();
        \\  const refs = instance.refs;
        \\
    );
    for (render_tree.nodes) |node| {
        try emitCreateNode(node, "fragment", scope_id, out, allocator, 1, "instance.refresh()", "refs");
    }
    try out.appendSlice(allocator,
        \\  return fragment;
        \\}
        \\
    );
}

pub fn emitCreateNode(
    node: browser_render_tree.Node,
    parent_ref: []const u8,
    scope_id: []const u8,
    out: *std.ArrayList(u8),
    allocator: std.mem.Allocator,
    indent: usize,
    scope_expr: []const u8,
    refs_expr: []const u8,
) !void {
    switch (node) {
        .text => |text| {
            try common.writeIndent(indent, out, allocator);
            try out.print(allocator, "{s}.append(document.createTextNode(", .{parent_ref});
            try common.emitHtmlString(text.content, out, allocator);
            try out.appendSlice(allocator, "));\n");
        },
        .interpolation => |interp| {
            const var_name = try common.refVarName(interp.ref_id, allocator);
            defer allocator.free(var_name);
            try common.writeIndent(indent, out, allocator);
            try out.print(allocator, "const {s} = document.createTextNode(\"\");\n", .{var_name});
            try common.writeIndent(indent, out, allocator);
            try out.print(allocator, "{s}[{d}] = {s};\n", .{ refs_expr, interp.ref_id, var_name });
            try common.writeIndent(indent, out, allocator);
            try out.print(allocator, "{s}.append({s});\n", .{ parent_ref, var_name });
        },
        .slot_outlet => |slot_outlet| {
            const start_var_name = try common.refVarName(slot_outlet.start_ref_id, allocator);
            defer allocator.free(start_var_name);
            const end_var_name = try common.refVarName(slot_outlet.end_ref_id, allocator);
            defer allocator.free(end_var_name);
            const slot_var_name = try std.fmt.allocPrint(allocator, "__slot_{d}", .{slot_outlet.handle_ref_id});
            defer allocator.free(slot_var_name);
            try common.writeIndent(indent, out, allocator);
            try out.print(allocator, "const {s} = document.createComment(\"slot:start\");\n", .{start_var_name});
            try common.writeIndent(indent, out, allocator);
            try out.print(allocator, "const {s} = document.createComment(\"slot:end\");\n", .{end_var_name});
            try common.writeIndent(indent, out, allocator);
            try out.print(allocator, "{s}[{d}] = {s};\n", .{ refs_expr, slot_outlet.start_ref_id, start_var_name });
            try common.writeIndent(indent, out, allocator);
            try out.print(allocator, "{s}[{d}] = {s};\n", .{ refs_expr, slot_outlet.end_ref_id, end_var_name });
            try common.writeIndent(indent, out, allocator);
            try out.print(allocator, "{s}[{d}] = false;\n", .{ refs_expr, slot_outlet.handle_ref_id });
            try common.writeIndent(indent, out, allocator);
            try out.print(allocator, "{s}.append({s});\n", .{ parent_ref, start_var_name });
            try common.writeIndent(indent, out, allocator);
            try out.print(allocator, "{s}.append({s});\n", .{ parent_ref, end_var_name });
            try slot_codegen.emitSlotLookupLine(slot_outlet, slot_var_name, indent, out, allocator);
            try common.writeIndent(indent, out, allocator);
            try out.print(allocator, "if ({s}) {{\n", .{slot_var_name});
            try common.writeIndent(indent + 1, out, allocator);
            try out.print(allocator, "{s}[{d}] = {s}.mountIntoBoundary({s}, {s});\n", .{
                refs_expr,
                slot_outlet.handle_ref_id,
                slot_var_name,
                start_var_name,
                end_var_name,
            });
            try common.writeIndent(indent, out, allocator);
            try out.appendSlice(allocator, "} else {\n");
            try slot_codegen.emitSlotFallbackReplaceLine(slot_outlet, start_var_name, end_var_name, scope_expr, indent + 1, out, allocator);
            try common.writeIndent(indent, out, allocator);
            try out.appendSlice(allocator, "}\n");
        },
        .element => |element| {
            const var_name = try common.refVarName(element.ref_id, allocator);
            defer allocator.free(var_name);
            try common.writeIndent(indent, out, allocator);
            if (std.mem.eql(u8, element.tag_name, "svg")) {
                try out.print(allocator, "const {s} = document.createElementNS(\"http://www.w3.org/2000/svg\", \"svg\");\n", .{var_name});
            } else {
                try out.print(allocator, "const {s} = ({s}.namespaceURI === \"http://www.w3.org/2000/svg\" && {s}.localName !== \"foreignObject\") || {s}.__weiv_namespace === \"http://www.w3.org/2000/svg\" ? document.createElementNS(\"http://www.w3.org/2000/svg\", \"{s}\") : document.createElement(\"{s}\");\n", .{ var_name, parent_ref, parent_ref, parent_ref, element.tag_name, element.tag_name });
            }
            try common.writeIndent(indent, out, allocator);
            try out.print(allocator, "{s}[{d}] = {s};\n", .{ refs_expr, element.ref_id, var_name });
            try common.writeIndent(indent, out, allocator);
            try out.print(allocator, "{s}.setAttribute(\"data-weiv-scope\", \"{s}\");\n", .{ var_name, scope_id });
            for (element.attributes) |attribute| {
                try common.writeIndent(indent, out, allocator);
                if (std.mem.eql(u8, attribute.name, "style")) {
                    try out.print(allocator, "{s}.style.cssText = ", .{var_name});
                } else {
                    try out.print(allocator, "{s}.setAttribute(\"{s}\", ", .{ var_name, attribute.name });
                }
                try common.emitHtmlString(attribute.value orelse "", out, allocator);
                try out.appendSlice(allocator, if (std.mem.eql(u8, attribute.name, "style")) ";\n" else ");\n");
            }
            for (element.event_effects) |effect| {
                switch (effect) {
                    .event => |event_dir| {
                        try common.writeIndent(indent, out, allocator);
                        try out.print(allocator, "{s}.addEventListener(\"{s}\", (event) => runOwnedBoundary(instance, () => {{\n", .{ var_name, event_dir.event_name });
                        try common.writeIndent(indent + 1, out, allocator);
                        try out.appendSlice(allocator, "const resolved = ");
                        try expression_codegen.emitResolvedExpression(event_dir.expression, scope_expr, "", out, allocator);
                        try out.appendSlice(allocator, ";\n");
                        if (expression_codegen.isCellExpression(event_dir.expression)) {
                            try common.writeIndent(indent + 1, out, allocator);
                            try out.appendSlice(allocator, "return resolved;\n");
                            try common.writeIndent(indent, out, allocator);
                            try out.appendSlice(allocator, "}));\n");
                            continue;
                        }
                        try common.writeIndent(indent + 1, out, allocator);
                        try out.appendSlice(allocator, "if (typeof resolved === \"function\") {\n");
                        try common.writeIndent(indent + 2, out, allocator);
                        try out.appendSlice(allocator, "return resolved(event);\n");
                        try common.writeIndent(indent + 1, out, allocator);
                        try out.appendSlice(allocator, "}\n");
                        try common.writeIndent(indent + 1, out, allocator);
                        try out.appendSlice(allocator, "return resolved;\n");
                        try common.writeIndent(indent, out, allocator);
                        try out.appendSlice(allocator, "}));\n");
                    },
                    .bind => unreachable,
                }
            }
            for (element.children) |child| {
                try emitCreateNode(child, var_name, scope_id, out, allocator, indent, scope_expr, refs_expr);
            }
            try common.writeIndent(indent, out, allocator);
            try out.print(allocator, "{s}.append({s});\n", .{ parent_ref, var_name });
        },
        .conditional => |conditional| {
            const start_var_name = try common.refVarName(conditional.start_ref_id, allocator);
            defer allocator.free(start_var_name);
            const end_var_name = try common.refVarName(conditional.end_ref_id, allocator);
            defer allocator.free(end_var_name);
            try common.writeIndent(indent, out, allocator);
            try out.print(allocator, "const {s} = document.createComment(\"if:start\");\n", .{start_var_name});
            try common.writeIndent(indent, out, allocator);
            try out.print(allocator, "const {s} = document.createComment(\"if:end\");\n", .{end_var_name});
            try common.writeIndent(indent, out, allocator);
            try out.print(allocator, "{s}[{d}] = {s};\n", .{ refs_expr, conditional.start_ref_id, start_var_name });
            try common.writeIndent(indent, out, allocator);
            try out.print(allocator, "{s}[{d}] = {s};\n", .{ refs_expr, conditional.end_ref_id, end_var_name });
            try common.writeIndent(indent, out, allocator);
            try out.print(allocator, "{s}[{d}] = undefined;\n", .{ refs_expr, conditional.state_ref_id });
            try common.writeIndent(indent, out, allocator);
            try out.print(allocator, "{s}.append({s});\n", .{ parent_ref, start_var_name });
            try common.writeIndent(indent, out, allocator);
            try out.print(allocator, "{s}.append({s});\n", .{ parent_ref, end_var_name });
        },
        .component => |component_node| {
            const start_var_name = try common.refVarName(component_node.start_ref_id, allocator);
            defer allocator.free(start_var_name);
            const end_var_name = try common.refVarName(component_node.end_ref_id, allocator);
            defer allocator.free(end_var_name);
            const has_props = component_codegen.componentHasProps(component_node);
            const has_handlers = component_codegen.componentHasEventHandlers(component_node);
            const has_slots = component_codegen.componentHasSlots(component_node);
            const props_var_name = if (has_props)
                try std.fmt.allocPrint(allocator, "__props_{d}", .{component_node.handle_ref_id})
            else
                null;
            defer if (props_var_name) |name| allocator.free(name);
            const handlers_var_name = if (has_handlers)
                try std.fmt.allocPrint(allocator, "__handlers_{d}", .{component_node.handle_ref_id})
            else
                null;
            defer if (handlers_var_name) |name| allocator.free(name);
            const slots_var_name = if (has_slots)
                try std.fmt.allocPrint(allocator, "__slots_{d}", .{component_node.handle_ref_id})
            else
                null;
            defer if (slots_var_name) |name| allocator.free(name);
            try common.writeIndent(indent, out, allocator);
            try out.print(allocator, "const {s} = document.createComment(\"component:start\");\n", .{start_var_name});
            try common.writeIndent(indent, out, allocator);
            try out.print(allocator, "const {s} = document.createComment(\"component:end\");\n", .{end_var_name});
            try common.writeIndent(indent, out, allocator);
            try out.print(allocator, "{s}[{d}] = {s};\n", .{ refs_expr, component_node.start_ref_id, start_var_name });
            try common.writeIndent(indent, out, allocator);
            try out.print(allocator, "{s}[{d}] = {s};\n", .{ refs_expr, component_node.end_ref_id, end_var_name });
            try common.writeIndent(indent, out, allocator);
            try out.print(allocator, "{s}.append({s});\n", .{ parent_ref, start_var_name });
            try common.writeIndent(indent, out, allocator);
            try out.print(allocator, "{s}.append({s});\n", .{ parent_ref, end_var_name });
            if (props_var_name) |name| {
                try common.writeIndent(indent, out, allocator);
                try out.print(allocator, "const {s} = ", .{name});
                try component_codegen.emitPropsObject(component_node.bind_effects, out, allocator, scope_expr, "");
                try out.appendSlice(allocator, ";\n");
            }
            if (handlers_var_name) |name| {
                try common.writeIndent(indent, out, allocator);
                try out.print(allocator, "const {s} = ", .{name});
                try component_codegen.emitChildHandlersObject(component_node.event_effects, out, allocator, scope_expr, "");
                try out.appendSlice(allocator, ";\n");
            }
            if (has_slots) {
                try common.writeIndent(indent, out, allocator);
                try out.print(allocator, "const {s} = ", .{slots_var_name.?});
                try common.emitProjectedSlotObject(component_node, "instance", out, allocator);
                try out.appendSlice(allocator, ";\n");
            }
            try common.writeIndent(indent, out, allocator);
            try out.print(allocator, "{s}[{d}] = {s}.mountIntoBoundary({s}, {s}, {s}, {s}, {s});\n", .{
                refs_expr,
                component_node.handle_ref_id,
                component_node.tag_name,
                start_var_name,
                end_var_name,
                props_var_name orelse "undefined",
                handlers_var_name orelse "undefined",
                slots_var_name orelse "undefined",
            });
        },
        .for_loop => |for_loop| {
            const start_var_name = try common.refVarName(for_loop.start_ref_id, allocator);
            defer allocator.free(start_var_name);
            const end_var_name = try common.refVarName(for_loop.end_ref_id, allocator);
            defer allocator.free(end_var_name);
            try common.writeIndent(indent, out, allocator);
            try out.print(allocator, "const {s} = document.createComment(\"for:start\");\n", .{start_var_name});
            try common.writeIndent(indent, out, allocator);
            try out.print(allocator, "const {s} = document.createComment(\"for:end\");\n", .{end_var_name});
            try common.writeIndent(indent, out, allocator);
            try out.print(allocator, "{s}[{d}] = {s};\n", .{ refs_expr, for_loop.start_ref_id, start_var_name });
            try common.writeIndent(indent, out, allocator);
            try out.print(allocator, "{s}[{d}] = {s};\n", .{ refs_expr, for_loop.end_ref_id, end_var_name });
            try common.writeIndent(indent, out, allocator);
            try out.print(allocator, "{s}[{d}] = [];\n", .{ refs_expr, for_loop.state_ref_id });
            try common.writeIndent(indent, out, allocator);
            try out.print(allocator, "{s}.append({s});\n", .{ parent_ref, start_var_name });
            try common.writeIndent(indent, out, allocator);
            try out.print(allocator, "{s}.append({s});\n", .{ parent_ref, end_var_name });
        },
    }
}
