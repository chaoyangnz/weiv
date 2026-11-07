const std = @import("std");
const sir = @import("sir.zig");

const JsonScriptFacts = struct {
    ok: bool,
    source_path: []const u8,
    transpiled_code: []const u8,
    props: ?JsonPropsFacts,
    imports: []JsonScriptImport,
    bindings: []JsonScriptBinding,
    state_analysis: ?JsonStateFacts,
    diagnostics: []JsonScriptDiagnostic,
};

const JsonStateFacts = struct {
    helpers: []JsonHelperFacts = &.{},
    mutations: []JsonMutationFacts = &.{},
    aliases: []JsonAliasFacts = &.{},
    callback_registrations: []JsonCallbackRegistrationFacts = &.{},
};

const JsonPropsFacts = struct {
    has_props_export: bool,
    props_binding_name: ?[]const u8,
    props_type_name: ?[]const u8,
};

const JsonScriptImport = struct {
    source: []const u8,
    kind: []const u8,
    imported_name: ?[]const u8,
    local_name: []const u8,
    span_start: usize,
    span_end: usize,
};

const JsonScriptBinding = struct {
    name: []const u8,
    kind: []const u8,
    exported: bool,
    template_visible: bool,
    callable: bool,
    type_annotation: ?[]const u8,
    span_start: usize,
    span_end: usize,
};

const JsonScriptDiagnostic = struct {
    severity: []const u8,
    message: []const u8,
    span_start: usize,
    span_end: usize,
    line: u32,
    column: u32,
    code: ?[]const u8,
};

const JsonHelperFacts = struct {
    name: []const u8,
    kind: []const u8,
    span_start: usize,
    span_end: usize,
    reads: [][]const u8,
    writes: [][]const u8,
    calls: [][]const u8,
    async_flag: bool,
    returns_expression_only: bool,
    contains_external_reads: bool,
    contains_side_effects: bool,
};

const JsonMutationFacts = struct {
    binding: []const u8,
    kind: []const u8,
    span_start: usize,
    span_end: usize,
    statement_position: bool,
    member_path: ?[]const u8,
    inside_callback: bool,
    callback_owned_candidate: bool,
};

const JsonAliasFacts = struct {
    alias: []const u8,
    target: []const u8,
    kind: []const u8,
    span_start: usize,
    span_end: usize,
};

const JsonCallbackRegistrationFacts = struct {
    callee: []const u8,
    callback_kind: []const u8,
    callback_span_start: usize,
    callback_span_end: usize,
    owned_candidate: bool,
    reason: []const u8,
};

pub const DecodedScript = struct {
    facts: sir.ScriptFacts,
    transpiled_code: []const u8,
};

pub fn decode(json_source: []const u8, allocator: std.mem.Allocator) !DecodedScript {
    const parsed = try std.json.parseFromSlice(JsonScriptFacts, allocator, json_source, .{
        .ignore_unknown_fields = true,
        .allocate = .alloc_always,
    });
    defer parsed.deinit();

    var imports = try allocator.alloc(sir.ScriptImport, parsed.value.imports.len);
    errdefer allocator.free(imports);
    for (parsed.value.imports, 0..) |record, idx| {
        imports[idx] = .{
            .source = try allocator.dupe(u8, record.source),
            .kind = try allocator.dupe(u8, record.kind),
            .imported_name = if (record.imported_name) |value| try allocator.dupe(u8, value) else null,
            .local_name = try allocator.dupe(u8, record.local_name),
            .span_start = record.span_start,
            .span_end = record.span_end,
        };
    }

    var bindings = try allocator.alloc(sir.ScriptBinding, parsed.value.bindings.len);
    errdefer allocator.free(bindings);
    for (parsed.value.bindings, 0..) |record, idx| {
        bindings[idx] = .{
            .name = try allocator.dupe(u8, record.name),
            .kind = try allocator.dupe(u8, record.kind),
            .exported = record.exported,
            .template_visible = record.template_visible,
            .callable = record.callable,
            .type_annotation = if (record.type_annotation) |value| try allocator.dupe(u8, value) else null,
            .span_start = record.span_start,
            .span_end = record.span_end,
        };
    }

    var diagnostics = try allocator.alloc(sir.ScriptDiagnostic, parsed.value.diagnostics.len);
    errdefer allocator.free(diagnostics);
    for (parsed.value.diagnostics, 0..) |record, idx| {
        diagnostics[idx] = .{
            .severity = try allocator.dupe(u8, record.severity),
            .message = try allocator.dupe(u8, record.message),
            .span_start = record.span_start,
            .span_end = record.span_end,
            .line = record.line,
            .column = record.column,
            .code = if (record.code) |value| try allocator.dupe(u8, value) else null,
        };
    }

    const parsed_state = parsed.value.state_analysis orelse JsonStateFacts{};

    var helpers = try allocator.alloc(sir.HelperFacts, parsed_state.helpers.len);
    errdefer allocator.free(helpers);
    for (parsed_state.helpers, 0..) |record, idx| {
        helpers[idx] = .{
            .name = try allocator.dupe(u8, record.name),
            .kind = try allocator.dupe(u8, record.kind),
            .span_start = record.span_start,
            .span_end = record.span_end,
            .reads = try dupeStringSlice2D(record.reads, allocator),
            .writes = try dupeStringSlice2D(record.writes, allocator),
            .calls = try dupeStringSlice2D(record.calls, allocator),
            .async_flag = record.async_flag,
            .returns_expression_only = record.returns_expression_only,
            .contains_external_reads = record.contains_external_reads,
            .contains_side_effects = record.contains_side_effects,
        };
    }

    var mutations = try allocator.alloc(sir.MutationFacts, parsed_state.mutations.len);
    errdefer allocator.free(mutations);
    for (parsed_state.mutations, 0..) |record, idx| {
        mutations[idx] = .{
            .binding = try allocator.dupe(u8, record.binding),
            .kind = try allocator.dupe(u8, record.kind),
            .span_start = record.span_start,
            .span_end = record.span_end,
            .statement_position = record.statement_position,
            .member_path = if (record.member_path) |value| try allocator.dupe(u8, value) else null,
            .inside_callback = record.inside_callback,
            .callback_owned_candidate = record.callback_owned_candidate,
        };
    }

    var aliases = try allocator.alloc(sir.AliasFacts, parsed_state.aliases.len);
    errdefer allocator.free(aliases);
    for (parsed_state.aliases, 0..) |record, idx| {
        aliases[idx] = .{
            .alias = try allocator.dupe(u8, record.alias),
            .target = try allocator.dupe(u8, record.target),
            .kind = try allocator.dupe(u8, record.kind),
            .span_start = record.span_start,
            .span_end = record.span_end,
        };
    }

    var callbacks = try allocator.alloc(sir.CallbackRegistrationFacts, parsed_state.callback_registrations.len);
    errdefer allocator.free(callbacks);
    for (parsed_state.callback_registrations, 0..) |record, idx| {
        callbacks[idx] = .{
            .callee = try allocator.dupe(u8, record.callee),
            .callback_kind = try allocator.dupe(u8, record.callback_kind),
            .callback_span_start = record.callback_span_start,
            .callback_span_end = record.callback_span_end,
            .owned_candidate = record.owned_candidate,
            .reason = try allocator.dupe(u8, record.reason),
        };
    }

    const facts: sir.ScriptFacts = .{
        .ok = parsed.value.ok,
        .source_path = try allocator.dupe(u8, parsed.value.source_path),
        .props = if (parsed.value.props) |props| .{
            .has_props_export = props.has_props_export,
            .props_binding_name = if (props.props_binding_name) |value| try allocator.dupe(u8, value) else null,
            .props_type_name = if (props.props_type_name) |value| try allocator.dupe(u8, value) else null,
        } else null,
        .imports = imports,
        .bindings = bindings,
        .state_facts = .{
            .helpers = helpers,
            .mutations = mutations,
            .aliases = aliases,
            .callback_registrations = callbacks,
        },
        .diagnostics = diagnostics,
    };
    return .{
        .facts = facts,
        .transpiled_code = try allocator.dupe(u8, parsed.value.transpiled_code),
    };
}

fn dupeStringSlice2D(values: [][]const u8, allocator: std.mem.Allocator) ![][]const u8 {
    var out = try allocator.alloc([]const u8, values.len);
    for (values, 0..) |value, idx| {
        out[idx] = try allocator.dupe(u8, value);
    }
    return out;
}
