const std = @import("std");
const component = @import("../component_unit.zig");
const diagnostics = @import("../diagnostics.zig");
const backend = @import("../../ffi/script_backend.zig");
const normalized = @import("../parser/template/normalized.zig");

const Import = struct { local: []const u8, imported: []const u8, source: []const u8 };
const Access = struct { name: []const u8, path: ?[]const u8 = null, call: bool = false };
const Coercion = struct { name: []const u8, path: ?[]const u8 = null, hint: u8 = 1, native: ?[]const u8 = null };
const CallEffect = struct { value: ValueShape, hint: u8, native: ?[]const u8 = null, option: ?*const ValueShape = null };
const CallCount = struct { name: []const u8, count: usize };
const ShapeProperty = struct { name: ?[]const u8 = null, value: ValueShape };
const ValueShape = struct {
    callee: ?[]const u8 = null,
    callee_value: ?*const ValueShape = null,
    native_callee: bool = false,
    member_call: bool = false,
    string_value: ?[]const u8 = null,
    lexical_this: bool = false,
    effects: []const CallEffect = &.{},
    kind: []const u8 = "",
    name: ?[]const u8 = null,
    path: ?[]const u8 = null,
    factory: ?[]const u8 = null,
    parameter_index: ?usize = null,
    scope_id: ?u64 = null,
    rest_parameter: bool = false,
    arguments_expanded: bool = false,
    truthy: ?bool = null,
    nullish: ?bool = null,
    values: []const ValueShape = &.{},
    properties: []const ShapeProperty = &.{},
    returns: []const ValueShape = &.{},
    captured_locals: []const []const u8 = &.{},
    captured_shapes: []const ValueShape = &.{},
    captured_opaque_paths: []const []const u8 = &.{},
    invocation: ?*const ValueShape = null,
    async_result: bool = false,
    generator_result: bool = false,
    accesses: []const Access = &.{},
    coercions: []const Coercion = &.{},
    calls: []const []const u8 = &.{},
    globals: []const []const u8 = &.{},
    has_mutation: bool = false,
    retained_local_state: bool = false,
    retained_local_calls: []const []const u8 = &.{},
    result_projections: []const []const u8 = &.{},
};
const Binding = struct {
    name: []const u8,
    declaration_kind: []const u8,
    value_kind: []const u8,
    alias: ?[]const u8 = null,
    factory: ?[]const u8 = null,
    reads: []const []const u8 = &.{},
    writes: []const []const u8 = &.{},
    globals: []const []const u8 = &.{},
    has_mutation: bool = false,
    retained_local_state: bool = false,
    retained_local_calls: []const []const u8 = &.{},
    result_projections: []const []const u8 = &.{},
    calls: []const []const u8 = &.{},
    accesses: []const Access = &.{},
    coercions: []const Coercion = &.{},
    effects: []const CallEffect = &.{},
    call_counts: []const CallCount = &.{},
    reference_counts: []const CallCount = &.{},
    shape: ValueShape = .{},
};
const Export = struct {
    exported: []const u8,
    local: ?[]const u8 = null,
    source: ?[]const u8 = null,
    imported: ?[]const u8 = null,
    kind: []const u8,
};
const Assignment = struct {
    target: []const u8,
    path: ?[]const u8 = null,
    dynamic_path: bool = false,
    operator: []const u8,
    projected: bool = false,
    inputs: []const []const u8 = &.{},
    value: Binding,
};
const ArgumentFlow = struct { target: []const u8, callee: []const u8, spread: bool = false, indirect: bool = false, argument_index: usize = 0 };
const Facts = struct {
    ok: bool,
    imports: []const Import,
    bindings: []const Binding,
    exports: []const Export,
    root_writes: []const []const u8 = &.{},
    assignments: []const Assignment = &.{},
    argument_flows: []const ArgumentFlow = &.{},
    iterable_mutations: []const []const u8 = &.{},
    dynamic_access: bool = false,
};
const Node = struct { path: []const u8, parsed: std.json.Parsed(Facts), component: bool = false };
const Origin = struct { node: ?*Node = null, external: ?[]const u8 = null, name: []const u8 };
const ExportResolution = union(enum) { missing, unknown, ambiguous, found: Origin };
const Trail = struct { node: *Node, name: []const u8, exported: bool };

pub const Subscription = struct {
    module_path: []const u8,
    name: []const u8,
    component_path: []const u8,
    binding: []const u8,
    watch: bool = true,
};

pub const ManagedPlan = struct {
    subscriptions: std.ArrayList(Subscription) = .empty,
    locals: std.ArrayList(struct { component_path: []const u8, name: []const u8 }) = .empty,
    local_subscriptions: std.ArrayList(struct { component_path: []const u8, name: []const u8, binding: []const u8, publisher_backed: bool = false }) = .empty,

    pub fn deinit(self: *ManagedPlan, allocator: std.mem.Allocator) void {
        for (self.subscriptions.items) |item| {
            allocator.free(item.module_path);
            allocator.free(item.name);
            allocator.free(item.component_path);
            allocator.free(item.binding);
        }
        self.subscriptions.deinit(allocator);
        for (self.locals.items) |item| {
            allocator.free(item.component_path);
            allocator.free(item.name);
        }
        self.locals.deinit(allocator);
        for (self.local_subscriptions.items) |item| {
            allocator.free(item.component_path);
            allocator.free(item.name);
            allocator.free(item.binding);
        }
        self.local_subscriptions.deinit(allocator);
    }

    fn watchLocal(self: *ManagedPlan, allocator: std.mem.Allocator, component_path: []const u8, name: []const u8, binding: []const u8) !void {
        try self.selectLocal(allocator, component_path, name);
        return self.watchImported(allocator, component_path, name, binding, false);
    }

    fn watchImported(self: *ManagedPlan, allocator: std.mem.Allocator, component_path: []const u8, name: []const u8, binding: []const u8, publisher_backed: bool) !void {
        for (self.local_subscriptions.items) |*item| if (std.mem.eql(u8, item.component_path, component_path) and std.mem.eql(u8, item.name, name) and std.mem.eql(u8, item.binding, binding)) {
            item.publisher_backed = item.publisher_backed or publisher_backed;
            return;
        };
        const owned_path = try allocator.dupe(u8, component_path);
        errdefer allocator.free(owned_path);
        const owned_name = try allocator.dupe(u8, name);
        errdefer allocator.free(owned_name);
        const owned_binding = try allocator.dupe(u8, binding);
        errdefer allocator.free(owned_binding);
        try self.local_subscriptions.append(allocator, .{ .component_path = owned_path, .name = owned_name, .binding = owned_binding, .publisher_backed = publisher_backed });
    }

    fn selectLocal(self: *ManagedPlan, allocator: std.mem.Allocator, component_path: []const u8, name: []const u8) !void {
        for (self.locals.items) |item| if (std.mem.eql(u8, item.component_path, component_path) and std.mem.eql(u8, item.name, name)) return;
        const owned_path = try allocator.dupe(u8, component_path);
        errdefer allocator.free(owned_path);
        const owned_name = try allocator.dupe(u8, name);
        errdefer allocator.free(owned_name);
        try self.locals.append(allocator, .{ .component_path = owned_path, .name = owned_name });
    }

    fn select(self: *ManagedPlan, allocator: std.mem.Allocator, module_path: []const u8, name: []const u8, component_path: []const u8, binding: []const u8) !void {
        return self.selectMode(allocator, module_path, name, component_path, binding, true);
    }

    fn normalize(self: *ManagedPlan, allocator: std.mem.Allocator, module_path: []const u8, name: []const u8, component_path: []const u8) !void {
        return self.selectMode(allocator, module_path, name, component_path, "", false);
    }

    fn selectMode(self: *ManagedPlan, allocator: std.mem.Allocator, module_path: []const u8, name: []const u8, component_path: []const u8, binding: []const u8, watch: bool) !void {
        for (self.subscriptions.items) |item| {
            if (item.watch == watch and std.mem.eql(u8, item.module_path, module_path) and std.mem.eql(u8, item.name, name) and std.mem.eql(u8, item.component_path, component_path) and std.mem.eql(u8, item.binding, binding)) return;
        }
        const owned_module = try allocator.dupe(u8, module_path);
        errdefer allocator.free(owned_module);
        const owned_name = try allocator.dupe(u8, name);
        errdefer allocator.free(owned_name);
        const owned_component = try allocator.dupe(u8, component_path);
        errdefer allocator.free(owned_component);
        const owned_binding = try allocator.dupe(u8, binding);
        errdefer allocator.free(owned_binding);
        try self.subscriptions.append(allocator, .{ .module_path = owned_module, .name = owned_name, .component_path = owned_component, .binding = owned_binding, .watch = watch });
    }
};

// Parsing is never ownership. Only the entry component is cell-managed here;
// ordinary imported modules remain external until a build actually transforms them.
pub fn analyze(model: *const component.ComponentUnit, allocator: std.mem.Allocator) ![]diagnostics.Diagnostic {
    return analyzeManaged(model, null, null, allocator);
}

pub fn analyzeManaged(model: *const component.ComponentUnit, root: ?[]const u8, plan: ?*ManagedPlan, allocator: std.mem.Allocator) ![]diagnostics.Diagnostic {
    var context = Context{
        .allocator = allocator,
        .model = model,
        .nodes = std.StringHashMap(*Node).init(allocator),
        .bag = diagnostics.DiagnosticBag.init(),
        .managed_root = root,
        .plan = plan,
    };
    defer context.deinit();
    const resolved = try std.fs.path.resolve(allocator, &.{model.source_path});
    defer allocator.free(resolved);
    var script = std.ArrayList(u8).empty;
    defer script.deinit(allocator);
    try script.appendSlice(allocator, model.sfc_document.script.content);
    try script.appendSlice(allocator, "\n;const __weiv_templateExpressions=[");
    const template_functions = @import("template_functions.zig");
    const script_names = try template_functions.bindingNames(&model.script, allocator);
    defer allocator.free(script_names);
    var functions = template_functions.Collector{ .allocator = allocator, .script = &script, .template = model.sfc_document.template.content, .script_names = script_names };
    defer functions.records.deinit(allocator);
    defer functions.locals.deinit(allocator);
    try functions.walk(model.normalized_template.nodes);
    try script.appendSlice(allocator, "];\n");
    const entry = try context.parse(resolved, script.items, true);
    if (plan) |managed| for (entry.parsed.value.bindings) |helper| {
        if (!std.mem.eql(u8, helper.name, "__weiv_templateExpressions")) continue;
        for (helper.writes) |name| for (entry.parsed.value.bindings) |binding| {
            if (std.mem.eql(u8, binding.name, name) and contains(&.{ "let", "const", "var" }, binding.declaration_kind)) try managed.selectLocal(allocator, model.source_path, name);
        };
    };
    var locals = std.ArrayList([]const u8).empty;
    defer locals.deinit(allocator);
    try context.walk(entry, model.normalized_template.nodes, &locals);
    try context.markPublisherImports(entry);
    return context.bag.toOwnedSlice(allocator);
}

const LoopOrigin = struct { name: []const u8, expression: []const u8 };
const CallArguments = struct { node: *Node, values: []const ValueShape, expanded: bool = false, scope: ?*const ParameterScope = null, scoped: bool = false };
const ParameterScope = struct { caller: *Node, values: []const ValueShape, expanded: bool, parent: ?*const ParameterScope, owner: ?u64 = null, owner_node: ?*Node = null, argument_scope: ?*const ParameterScope = null, scoped_arguments: bool = false, receiver: ?ParameterValue = null };
const ParameterValue = struct { node: *Node, shape: ValueShape, scope: ?*const ParameterScope };
const CallableOrigin = struct { node: *Node, scope_id: ?u64 };
const NativeArguments = struct {
    values: std.ArrayList(ParameterValue) = .empty,
    frames: std.ArrayList(*ParameterScope) = .empty,

    fn addFrame(self: *NativeArguments, allocator: std.mem.Allocator, value: ParameterScope) !*ParameterScope {
        const frame = try allocator.create(ParameterScope);
        errdefer allocator.destroy(frame);
        try self.frames.append(allocator, frame);
        frame.* = value;
        return frame;
    }

    fn deinit(self: *NativeArguments, allocator: std.mem.Allocator) void {
        for (self.frames.items) |frame| allocator.destroy(frame);
        self.frames.deinit(allocator);
        self.values.deinit(allocator);
    }
};

// Template expressions are parsed separately from the script. Give their
// lexical scopes a distinct domain before resolving them against script bindings.
fn rebaseScopes(shape: *ValueShape, domain: u64) void {
    if (shape.scope_id) |scope| shape.scope_id = (domain << 32) | scope;
    if (shape.callee_value) |callee| rebaseScopes(@constCast(callee), domain);
    if (shape.invocation) |invocation| rebaseScopes(@constCast(invocation), domain);
    for (@constCast(shape.values)) |*value| rebaseScopes(value, domain);
    for (@constCast(shape.returns)) |*value| rebaseScopes(value, domain);
    for (@constCast(shape.captured_shapes)) |*value| rebaseScopes(value, domain);
    for (@constCast(shape.properties)) |*property| rebaseScopes(&property.value, domain);
    for (@constCast(shape.effects)) |*effect| {
        rebaseScopes(&effect.value, domain);
        if (effect.option) |option| rebaseScopes(@constCast(option), domain);
    }
}
const Context = struct {
    allocator: std.mem.Allocator,
    model: *const component.ComponentUnit,
    nodes: std.StringHashMap(*Node),
    bag: diagnostics.DiagnosticBag,
    trail: std.ArrayList(Trail) = .empty,
    labels: std.ArrayList([]const u8) = .empty,
    indirect: usize = 0,
    use_span: diagnostics.Span = .{ .start = 0, .end = 0 },
    emitted: std.StringHashMap(void) = undefined,
    managed_root: ?[]const u8 = null,
    plan: ?*ManagedPlan = null,
    render_binding: []const u8 = "",
    invoking: bool = false,
    coercing: u8 = 0,
    receiver: ?ParameterValue = null,
    shallow_invocation: bool = false,
    converting_call: ?CallArguments = null,
    callable_resolved: ?*bool = null,
    spread_result: ?*NativeArguments = null,
    spread_proven: ?*bool = null,
    json_skip_hook: bool = false,
    json_key: []const u8 = "",
    expression_entry: ?*Node = null,
    covered_calls: ?*std.StringHashMap(void) = null,
    covered_callbacks: ?*std.StringHashMap(void) = null,
    loop_origins: std.ArrayList(LoopOrigin) = .empty,
    inspecting_contract: bool = false,
    inspecting_return: bool = false,
    parameters: ?*const ParameterScope = null,
    expression_serial: u64 = 0,
    callable_visits: usize = 0,
    callable_trail: std.ArrayList(CallableOrigin) = .empty,
    declaration_iterator: bool = false,
    owning_only: bool = false,

    fn owns(self: *Context, node: *Node) bool {
        const root = self.managed_root orelse return false;
        return !node.component and std.mem.startsWith(u8, node.path, root) and
            node.path.len > root.len and (node.path[root.len] == '/' or node.path[root.len] == '\\') and
            std.mem.indexOf(u8, node.path, "/node_modules/") == null and
            std.mem.indexOf(u8, node.path, "\\node_modules\\") == null;
    }

    fn markPublisherImports(self: *Context, entry: *Node) !void {
        const plan = self.plan orelse return;
        // Match actual export origins after all dependency paths are selected.
        // A managed live root must not also capture its initial object in an
        // imported cell: that would keep listening after root replacement.
        for (entry.parsed.value.imports) |record| {
            var seen = std.ArrayList(Trail).empty;
            defer seen.deinit(self.allocator);
            const resolved = try self.resolveImportOrigin(entry, record.source, record.imported, &seen);
            if (resolved != .found) continue;
            const origin = resolved.found.node orelse continue;
            for (plan.subscriptions.items) |subscription| {
                if (!subscription.watch) continue;
                if (!std.mem.eql(u8, subscription.module_path, origin.path) or
                    !std.mem.eql(u8, subscription.name, resolved.found.name) or
                    !std.mem.eql(u8, subscription.component_path, self.model.source_path)) continue;
                try plan.watchImported(self.allocator, self.model.source_path, record.local, subscription.binding, true);
                break;
            }
        }
    }

    fn deinit(self: *Context) void {
        self.callable_trail.deinit(self.allocator);
        var iterator = self.nodes.valueIterator();
        while (iterator.next()) |node| {
            node.*.parsed.deinit();
            self.allocator.free(node.*.path);
            self.allocator.destroy(node.*);
        }
        self.nodes.deinit();
        self.bag.deinit(self.allocator);
        self.trail.deinit(self.allocator);
        self.loop_origins.deinit(self.allocator);
        self.labels.deinit(self.allocator);
    }

    fn parse(self: *Context, path: []const u8, source: []const u8, owned_component: bool) !*Node {
        if (self.nodes.get(path)) |node| return node;
        const json = try backend.analyzeModuleStateRaw(source, path, self.allocator);
        defer self.allocator.free(json);
        const parsed = try std.json.parseFromSlice(Facts, self.allocator, json, .{ .ignore_unknown_fields = true, .allocate = .alloc_always });
        errdefer parsed.deinit();
        const node = try self.allocator.create(Node);
        errdefer self.allocator.destroy(node);
        node.* = .{ .path = try self.allocator.dupe(u8, path), .parsed = parsed, .component = owned_component };
        errdefer self.allocator.free(node.path);
        try self.nodes.put(node.path, node);
        return node;
    }

    fn imported(self: *Context, node: *Node, source: []const u8) !?*Node {
        if (!std.mem.startsWith(u8, source, ".")) return null;
        const base = try std.fs.path.resolve(self.allocator, &.{ std.fs.path.dirname(node.path) orelse ".", source });
        defer self.allocator.free(base);
        const extensions = [_][]const u8{ "", ".ts", ".mts", ".js", ".mjs", "/index.ts", "/index.js" };
        for (extensions) |suffix| {
            const candidate = try std.fmt.allocPrint(self.allocator, "{s}{s}", .{ base, suffix });
            defer self.allocator.free(candidate);
            // Never inspect type declarations as implementations or SFCs as JS.
            if (std.mem.endsWith(u8, candidate, ".d.ts") or std.mem.endsWith(u8, candidate, ".weiv")) continue;
            const path = std.Io.Dir.cwd().realPathFileAlloc(std.Io.Threaded.global_single_threaded.io(), candidate, self.allocator) catch continue;
            defer self.allocator.free(path);
            if (self.nodes.get(path)) |cached| return cached;
            const text = std.Io.Dir.cwd().readFileAlloc(std.Io.Threaded.global_single_threaded.io(), path, self.allocator, .limited(1024 * 1024)) catch |err| {
                if (err == error.IsDir) continue;
                if (err == error.OutOfMemory) return err;
                return null;
            };
            defer self.allocator.free(text);
            return try self.parse(path, text, false);
        }
        return null;
    }

    fn walk(self: *Context, entry: *Node, nodes: []const normalized.Node, locals: *std.ArrayList([]const u8)) anyerror!void {
        for (nodes) |node| switch (node) {
            .text => {},
            .interpolation => |value| try self.expression(entry, value.expression, value.span.start, locals.items, true),
            .conditional => |value| {
                try self.expression(entry, value.condition, value.span.start, locals.items, false);
                try self.walk(entry, value.consequent, locals);
                try self.walk(entry, value.alternate, locals);
            },
            .for_loop => |value| {
                try self.expression(entry, value.iterable_expr, value.span.start, locals.items, false);
                try locals.append(self.allocator, value.item_name);
                defer _ = locals.pop();
                try self.loop_origins.append(self.allocator, .{ .name = value.item_name, .expression = value.iterable_expr });
                defer _ = self.loop_origins.pop();
                try self.walk(entry, value.body, locals);
            },
            .slot_outlet => |value| try self.walk(entry, value.fallback_children, locals),
            .element => |value| {
                for (value.directives) |directive| switch (directive) {
                    .bind => |binding| try self.expression(entry, binding.expression, binding.span.start, locals.items, value.tag_name.len > 0 and std.ascii.isLower(value.tag_name[0]) and !contains(&.{ "checked", "disabled", "selected", "multiple", "readonly", "required", "hidden", "class", "style" }, binding.target_name)),
                    .event => {},
                    else => {},
                };
                try self.walk(entry, value.children, locals);
            },
        };
    }

    fn expression(self: *Context, entry: *Node, expression_source: []const u8, start: usize, locals: []const []const u8, rendered: bool) !void {
        const source = try std.fmt.allocPrint(self.allocator, "const __template = () => ({s});", .{expression_source});
        defer self.allocator.free(source);
        const raw = try backend.analyzeModuleStateRaw(source, "template.ts", self.allocator);
        defer self.allocator.free(raw);
        const parsed = try std.json.parseFromSlice(Facts, self.allocator, raw, .{ .ignore_unknown_fields = true });
        defer parsed.deinit();
        const template_start = self.model.sfc_document.template.content_span.start;
        const found = std.mem.indexOfPos(u8, self.model.sfc_document.template.content, start, expression_source) orelse start;
        self.use_span = .{ .start = template_start + found, .end = template_start + found + expression_source.len };
        self.emitted = std.StringHashMap(void).init(self.allocator);
        defer {
            var keys = self.emitted.keyIterator();
            while (keys.next()) |key| self.allocator.free(key.*);
            self.emitted.deinit();
        }
        if (!parsed.value.ok or parsed.value.bindings.len == 0) {
            try self.labels.append(self.allocator, "template expression");
            defer _ = self.labels.pop();
            try self.warning(false, "template dependency syntax could not be analyzed");
            return;
        }
        self.expression_serial += 1;
        self.callable_visits = 0;
        for (@constCast(parsed.value.bindings)) |*binding| {
            rebaseScopes(&binding.shape, self.expression_serial);
            for (@constCast(binding.effects)) |*effect| {
                rebaseScopes(&effect.value, self.expression_serial);
                if (effect.option) |option| rebaseScopes(@constCast(option), self.expression_serial);
            }
        }
        var covered = std.StringHashMap(void).init(self.allocator);
        defer covered.deinit();
        var callbacks = std.StringHashMap(void).init(self.allocator);
        defer callbacks.deinit();
        const previous_entry = self.expression_entry;
        const previous_covered = self.covered_calls;
        const previous_callbacks = self.covered_callbacks;
        self.expression_entry = entry;
        self.covered_calls = &covered;
        self.covered_callbacks = &callbacks;
        defer self.expression_entry = previous_entry;
        defer self.covered_calls = previous_covered;
        defer self.covered_callbacks = previous_callbacks;
        self.render_binding = "";
        for (parsed.value.bindings[0].accesses) |access| if (hasLocal(entry, access.name)) {
            self.render_binding = access.name;
            break;
        };
        try self.inspectEffects(entry, parsed.value.bindings[0].effects, true);
        if (rendered) for (parsed.value.bindings[0].shape.returns) |returned| try self.convertedResult(entry, returned, 1, 0, true);
        try self.projectedResults(entry, parsed.value.bindings[0].result_projections);
        try self.retainedCalls(entry, parsed.value.bindings[0].retained_local_calls);
        if (parsed.value.bindings[0].retained_local_state) try self.warning(false, "template callback retains raw local state outside managed declaration lowering; expose observable data");
        for (parsed.value.bindings[0].accesses) |access| {
            if (!access.call and access.path == null and callbacks.contains(access.name)) {
                var sites: usize = 0;
                for (parsed.value.bindings[0].reference_counts) |count| if (std.mem.eql(u8, count.name, access.name)) {
                    sites = count.count;
                };
                if (sites == 1) continue;
            }
            if (access.call) {
                const name = if (access.path) |path| try std.fmt.allocPrint(self.allocator, "{s}.{s}", .{ access.name, path }) else try self.allocator.dupe(u8, access.name);
                defer self.allocator.free(name);
                if (covered.contains(name)) {
                    var sites: usize = 0;
                    for (parsed.value.bindings[0].call_counts) |count| if (std.mem.eql(u8, count.name, name)) {
                        sites = count.count;
                    };
                    if (sites == 1) continue;
                }
            }
            const previous_coercion = self.coercing;
            self.coercing = coerces(entry, parsed.value.bindings[0].coercions, access);
            if (rendered) for (parsed.value.bindings[0].shape.returns) |returned| {
                if (try self.resultCoerces(entry, returned, access, 0)) self.coercing |= 1;
            };
            defer self.coercing = previous_coercion;
            if (contains(locals, access.name)) {
                try self.loopAccess(entry, access.name, access.path, access.call, self.loop_origins.items.len);
                continue;
            }
            try self.renderAccess(entry, access.name, access.path, access.call);
        }
    }

    fn effectKey(node: *Node, shape: ValueShape, depth: usize) ?[]const u8 {
        if (depth >= 32) return null;
        if (shape.name) |name| if (std.mem.eql(u8, shape.kind, "reference") and hasLocal(node, name)) return name;
        if (!std.mem.eql(u8, shape.kind, "native_arguments")) if (shape.callee) |callee| {
            const dot = std.mem.indexOfScalar(u8, callee, '.') orelse callee.len;
            if (hasLocal(node, callee[0..dot])) return callee[0..dot];
        };
        for (shape.accesses) |access| if (hasLocal(node, access.name)) return access.name;
        for (shape.properties) |property| if (effectKey(node, property.value, depth + 1)) |key| return key;
        for (shape.values) |value| if (effectKey(node, value, depth + 1)) |key| return key;
        return null;
    }

    fn inspectEffects(self: *Context, node: *Node, effects: []const CallEffect, cover: bool) anyerror!void {
        for (effects) |effect| {
            if (effect.native) |native| if (hasLocal(node, native)) continue;
            if (std.mem.eql(u8, effect.value.kind, "native_arguments")) {
                if (cover and self.render_binding.len == 0) if (effectKey(node, effect.value, 0)) |key| {
                    self.render_binding = key;
                };
                try self.inspectNativeArguments(node, effect, cover);
                continue;
            }
            if (effect.option) |option| {
                const ignored = try self.knownTest(node, option.*, true, 0);
                if (ignored == null or !ignored.?) try self.warning(false, "custom JSON replacer effects and property selection are unverified; use an explicit serialization/subscription adapter");
            }
            if (cover and self.render_binding.len == 0) if (effectKey(node, effect.value, 0)) |key| {
                self.render_binding = key;
            };
            try self.convertedResult(node, effect.value, effect.hint, 0, cover);
        }
    }

    fn expandNativeSpread(self: *Context, node: *Node, shape: ValueShape, expansion: *NativeArguments, depth: usize) anyerror!bool {
        const values = &expansion.values;
        if (depth >= 32 or values.items.len >= 128) return false;
        if (std.mem.eql(u8, shape.kind, "array")) {
            if (values.items.len + shape.values.len > 128) return false;
            for (shape.values) |value| {
                // Unknown/elided expansion metadata cannot prove positional arity.
                if (value.kind.len == 0) return false;
                try values.append(self.allocator, .{ .node = node, .shape = value, .scope = self.parameters });
            }
            return true;
        }
        if (std.mem.eql(u8, shape.kind, "parameter")) {
            if (shape.rest_parameter or try self.possibleDefault(node, shape)) return false;
            const value = self.parameterValue(node, shape) orelse return false;
            const previous = self.parameters;
            self.parameters = value.scope;
            defer self.parameters = previous;
            return self.expandNativeSpread(value.node, value.shape, expansion, depth + 1);
        }
        if (std.mem.eql(u8, shape.kind, "call") and shape.factory != null and shape.values.len > 0) {
            if (try self.factory(node, shape.factory.?, 0) != null) return self.expandNativeSpread(node, shape.values[0], expansion, depth + 1);
        }
        if (std.mem.eql(u8, shape.kind, "call")) {
            if (shape.callee orelse shape.factory) |callee| {
                if (try self.expandSpreadCall(node, callee, .{ .node = node, .values = shape.values, .expanded = shape.arguments_expanded }, expansion, depth + 1)) {
                    if (self.expression_entry == node) if (self.covered_calls) |covered| try covered.put(callee, {});
                    return true;
                }
            }
            if (shape.callee_value) |callee| {
                const previous_result = self.spread_result;
                const previous_proven = self.spread_proven;
                var proven = false;
                self.spread_result = expansion;
                self.spread_proven = &proven;
                defer self.spread_result = previous_result;
                defer self.spread_proven = previous_proven;
                try self.convertedCallable(node, callee.*, shape, depth + 1);
                return proven;
            }
            return false;
        }
        if (contains(&.{ "logical", "conditional", "sequence" }, shape.kind)) {
            if (try self.branchChoice(node, shape, depth + 1)) |index| return self.expandNativeSpread(node, shape.values[index], expansion, depth + 1);
            return false;
        }
        if (std.mem.eql(u8, shape.kind, "reference") and shape.name != null and shape.path == null) {
            const name = shape.name.?;
            if (contains(node.parsed.value.root_writes, name)) return false;
            for (node.parsed.value.imports) |record| {
                if (!std.mem.eql(u8, record.local, name)) continue;
                var seen = std.ArrayList(Trail).empty;
                defer seen.deinit(self.allocator);
                const resolved = try self.resolveImportOrigin(node, record.source, record.imported, &seen);
                if (resolved != .found or resolved.found.node == null) return false;
                return self.expandNativeSpread(resolved.found.node.?, .{ .kind = "reference", .name = resolved.found.name }, expansion, depth + 1);
            }
            for (node.parsed.value.assignments) |assignment| if (std.mem.eql(u8, assignment.target, name)) {
                try self.warning(false, if (self.declaration_iterator) "array destructuring source is mutated; iterator values and alias ownership are unverified" else "spread argument array is mutated; conversion positions and later hook dependencies are unverified");
                break;
            };
            if (contains(node.parsed.value.iterable_mutations, name)) try self.warning(false, if (self.declaration_iterator) "array destructuring source is mutated; iterator values and alias ownership are unverified" else "spread argument array is mutated; conversion positions and later hook dependencies are unverified");
            for (node.parsed.value.bindings) |binding| if (std.mem.eql(u8, binding.name, name)) return self.expandNativeSpread(node, binding.shape, expansion, depth + 1);
        }
        return false;
    }

    fn expandSpreadCall(self: *Context, node: *Node, name: []const u8, arguments: CallArguments, expansion: *NativeArguments, depth: usize) anyerror!bool {
        if (depth >= 32 or expansion.frames.items.len >= 128) return false;
        if (std.mem.indexOfScalar(u8, name, '.')) |dot| {
            var resolved = try self.namespaceRoot(node, name[0..dot], 0);
            var parts = std.mem.splitScalar(u8, name[dot + 1 ..], '.');
            while (parts.next()) |part| {
                if (resolved != .found or resolved.found.node == null or !std.mem.eql(u8, resolved.found.name, "*namespace*")) return false;
                var seen = std.ArrayList(Trail).empty;
                defer seen.deinit(self.allocator);
                resolved = try self.resolveExport(resolved.found.node.?, part, &seen);
            }
            if (resolved != .found or resolved.found.node == null) return false;
            return self.expandSpreadCall(resolved.found.node.?, resolved.found.name, arguments, expansion, depth + 1);
        }
        for (node.parsed.value.imports) |record| {
            if (!std.mem.eql(u8, record.local, name)) continue;
            var seen = std.ArrayList(Trail).empty;
            defer seen.deinit(self.allocator);
            const resolved = try self.resolveImportOrigin(node, record.source, record.imported, &seen);
            if (resolved != .found or resolved.found.node == null) return false;
            return self.expandSpreadCall(resolved.found.node.?, resolved.found.name, arguments, expansion, depth + 1);
        }
        for (node.parsed.value.bindings) |binding| {
            if (!std.mem.eql(u8, binding.name, name)) continue;
            if (contains(node.parsed.value.root_writes, name)) return false;
            if (std.mem.eql(u8, binding.value_kind, "alias") and binding.alias != null) return self.expandSpreadCall(node, binding.alias.?, arguments, expansion, depth + 1);
            if (!std.mem.eql(u8, binding.shape.kind, "function") or binding.shape.async_result or binding.shape.generator_result or binding.shape.returns.len != 1) return false;
            const label = try std.fmt.allocPrint(self.allocator, "{s}::{s}() spread result", .{ node.path, name });
            defer self.allocator.free(label);
            try self.labels.append(self.allocator, label);
            defer _ = self.labels.pop();
            const parameters = try expansion.addFrame(self.allocator, .{ .caller = arguments.node, .values = arguments.values, .expanded = arguments.expanded, .parent = self.parameters, .owner = binding.shape.scope_id, .owner_node = node });
            const previous = self.parameters;
            self.parameters = parameters;
            defer self.parameters = previous;
            if (!node.component) self.indirect += 1;
            defer if (!node.component) {
                self.indirect -= 1;
            };
            try self.retainedCalls(node, binding.retained_local_calls);
            if (binding.retained_local_state) try self.warning(false, "helper closures retain raw local state outside declaration lowering; create observable state inside the helper");
            if (binding.shape.invocation) |effects| {
                try self.traceInvocation(node, effects.*);
                if (effects.has_mutation) try self.warning(false, "helper spread result depends on mutations with unverified argument layout");
            }
            return self.expandNativeSpread(node, binding.shape.returns[0], expansion, depth + 1);
        }
        return false;
    }

    fn inspectNativeValue(self: *Context, value: ParameterValue, hint: u8, cover: bool) anyerror!void {
        const previous = self.parameters;
        self.parameters = value.scope;
        defer self.parameters = previous;
        try self.convertedResult(value.node, value.shape, hint, 0, cover);
    }

    fn inspectNativeArguments(self: *Context, node: *Node, effect: CallEffect, cover: bool) anyerror!void {
        var expansion = NativeArguments{};
        defer expansion.deinit(self.allocator);
        const values = &expansion.values;
        for (effect.value.values) |value| {
            if (std.mem.eql(u8, value.kind, "spread")) {
                if (value.values.len != 1 or !try self.expandNativeSpread(node, value.values[0], &expansion, 0)) {
                    try self.warning(false, "native spread argument layout or iterator effects are unverified; pass explicit arguments or use a subscription adapter");
                    return;
                }
            } else {
                if (values.items.len >= 128) return self.warning(false, "native spread argument analysis exceeds the argument limit");
                try values.append(self.allocator, .{ .node = node, .shape = value, .scope = self.parameters });
            }
        }
        const operation = effect.value.callee orelse return;
        const native = effect.native orelse return;
        if (std.mem.eql(u8, native, "JSON")) {
            if (values.items.len > 1) {
                const option = values.items[1];
                const previous = self.parameters;
                self.parameters = option.scope;
                defer self.parameters = previous;
                const ignored = try self.knownTest(option.node, option.shape, true, 0);
                if (ignored == null or !ignored.?) try self.warning(false, "custom JSON replacer effects and property selection are unverified; use an explicit serialization/subscription adapter");
            }
            if (values.items.len > 0) try self.inspectNativeValue(values.items[0], 8, cover);
            return;
        }
        if (contains(&.{ "hasOwn", "hasOwnProperty", "propertyIsEnumerable" }, operation)) {
            const index: usize = if (std.mem.eql(u8, operation, "hasOwn")) 1 else 0;
            if (values.items.len > index) try self.inspectNativeValue(values.items[index], 1, cover);
            return;
        }
        if (std.mem.eql(u8, native, "Math")) {
            const count = if (contains(&.{ "max", "min", "hypot" }, operation)) values.items.len else if (contains(&.{ "atan2", "imul", "pow" }, operation)) @min(2, values.items.len) else @min(1, values.items.len);
            for (values.items[0..count]) |value| try self.inspectNativeValue(value, 2, cover);
            return;
        }
        if (values.items.len > 0) try self.inspectNativeValue(values.items[0], effect.hint, cover);
        if (std.mem.eql(u8, native, "parseInt") and values.items.len > 1) try self.inspectNativeValue(values.items[1], 2, cover);
    }

    fn arrayExpression(self: *Context, node: *Node, shape: ValueShape, method: []const u8, plain: bool, depth: usize) anyerror!bool {
        if (depth >= 32) return false;
        if (std.mem.eql(u8, shape.kind, "array")) return !plain or try self.plainTrackedShape(node, shape, 0);
        if (std.mem.eql(u8, shape.kind, "reference") and shape.name != null and shape.path == null) return try self.arrayBinding(node, shape.name.?, method, 0) and (!plain or try self.plainTrackedShape(node, shape, 0));
        if (std.mem.eql(u8, shape.kind, "call") and shape.callee_value != null) {
            const callee = shape.callee_value.?.*;
            if (std.mem.eql(u8, callee.kind, "projection") and callee.path != null and callee.values.len > 0 and contains(&.{ "map", "filter", "slice", "flat", "flatMap", "concat", "toReversed", "toSorted", "toSpliced", "with" }, callee.path.?)) return self.arrayExpression(node, callee.values[0], callee.path.?, true, depth + 1);
        }
        return false;
    }

    fn nativeArrayConversion(self: *Context, node: *Node, shape: ValueShape, hint: u8) anyerror!bool {
        if (hint & 8 != 0 or shape.callee_value == null) return false;
        const callee = shape.callee_value.?.*;
        if (!std.mem.eql(u8, callee.kind, "projection") or callee.path == null or callee.values.len == 0) return false;
        const method = callee.path.?;
        if (contains(&.{ "join", "toString", "toLocaleString", "some", "every", "includes", "indexOf", "lastIndexOf", "findIndex", "findLastIndex" }, method)) return self.arrayExpression(node, callee.values[0], method, false, 0);
        if (contains(&.{ "map", "filter", "slice", "flat", "flatMap", "concat", "toReversed", "toSorted", "toSpliced", "with", "at", "find", "findLast" }, method)) return self.arrayExpression(node, callee.values[0], method, true, 0);
        return false;
    }

    fn convertedResult(self: *Context, node: *Node, shape: ValueShape, hint: u8, depth: usize, cover: bool) anyerror!void {
        if (depth >= 32) {
            try self.warning(false, "call-result conversion reached the analysis limit; expose supported observable data");
            return;
        }
        if (contains(&.{ "logical", "conditional", "sequence" }, shape.kind)) {
            if (try self.branchChoice(node, shape, depth + 1)) |index| return self.convertedResult(node, shape.values[index], hint, depth + 1, cover);
            const start: usize = if (std.mem.eql(u8, shape.kind, "conditional")) 1 else 0;
            for (shape.values[start..]) |value| try self.convertedResult(node, value, hint, depth + 1, cover);
            return;
        }
        if (try self.nativeArrayConversion(node, shape, hint)) return;
        const previous_coercion = self.coercing;
        const previous_invoking = self.invoking;
        self.coercing = hint;
        self.invoking = false;
        defer self.coercing = previous_coercion;
        defer self.invoking = previous_invoking;
        if (shape.callee) |callee| {
            const dot = std.mem.indexOfScalar(u8, callee, '.') orelse callee.len;
            const native = shape.native_callee and !hasLocal(node, callee[0..dot]);
            if (native and (std.mem.eql(u8, shape.kind, "primitive") or primitiveNativeResult(callee))) return;
            if (try self.inspectCallReturn(node, callee, null, false, depth + 1, .{ .node = node, .values = shape.values, .expanded = shape.arguments_expanded })) {
                if (cover and self.expression_entry == node) if (self.covered_calls) |covered| try covered.put(callee, {});
                return;
            }
            if (shape.callee_value) |value| return self.convertedCallable(node, value.*, shape, depth + 1);
            const label = try std.fmt.allocPrint(self.allocator, "{s}() conversion", .{callee});
            defer self.allocator.free(label);
            try self.labels.append(self.allocator, label);
            defer _ = self.labels.pop();
            try self.warning(false, "call-result conversion has unverified return-value effects; expose supported observable data");
            return;
        }
        if (std.mem.eql(u8, shape.kind, "call")) {
            if (shape.callee_value) |value| return self.convertedCallable(node, value.*, shape, depth + 1);
            try self.warning(false, "dynamic call-result conversion is unverified; expose supported observable data");
            return;
        }
        if (std.mem.eql(u8, shape.kind, "reference") and shape.name != null) {
            if (self.expression_entry == node) for (self.loop_origins.items) |origin| {
                if (std.mem.eql(u8, origin.name, shape.name.?)) return self.loopAccess(node, shape.name.?, shape.path, false, self.loop_origins.items.len);
            };
            if (hasLocal(node, shape.name.?)) return self.trace(node, shape.name.?, shape.path, false);
            if (!knownGlobal(shape.name.?)) return self.globalWarning(shape.name.?, shape.path);
            return;
        }
        if (std.mem.eql(u8, shape.kind, "local_reference")) return self.warning(false, "lexical conversion dependency could not be resolved; expose observable data or use an adapter");
        try self.inspectShape(node, shape, null, false, depth + 1);
    }

    fn convertedCallable(self: *Context, node: *Node, callee: ValueShape, call: ValueShape, depth: usize) anyerror!void {
        const label = try std.fmt.allocPrint(self.allocator, "{s}::{s}()", .{ node.path, call.name orelse call.callee orelse "contextual callable" });
        defer self.allocator.free(label);
        try self.labels.append(self.allocator, label);
        defer _ = self.labels.pop();
        const previous_call = self.converting_call;
        const previous_receiver = self.receiver;
        const previous_invoking = self.invoking;
        const previous_resolved = self.callable_resolved;
        var resolved = false;
        self.callable_resolved = &resolved;
        self.converting_call = .{ .node = node, .values = call.values, .expanded = call.arguments_expanded, .scope = self.parameters, .scoped = true };
        self.receiver = if (call.member_call and contains(&.{ "projection", "computed_projection" }, callee.kind) and callee.values.len > 0) .{ .node = node, .shape = callee.values[0], .scope = self.parameters } else null;
        self.invoking = true;
        defer self.converting_call = previous_call;
        defer self.receiver = previous_receiver;
        defer self.invoking = previous_invoking;
        defer self.callable_resolved = previous_resolved;
        try self.inspectShape(node, callee, null, false, depth + 1);
        if (!resolved) try self.warning(false, "callable invocation effects or result are unverified; expose a known callable or use a subscription adapter");
    }

    fn knownString(self: *Context, node: *Node, shape: ValueShape, depth: usize) anyerror!?[]const u8 {
        if (depth >= 32) return null;
        if (std.mem.eql(u8, shape.kind, "primitive")) return shape.string_value;
        if (std.mem.eql(u8, shape.kind, "parameter")) {
            if (try self.possibleDefault(node, shape)) return null;
            const value = self.parameterValue(node, shape) orelse return null;
            const previous = self.parameters;
            self.parameters = value.scope;
            defer self.parameters = previous;
            return self.knownString(value.node, value.shape, depth + 1);
        }
        if (contains(&.{ "logical", "conditional", "sequence" }, shape.kind)) {
            if (try self.branchChoice(node, shape, depth + 1)) |index| return self.knownString(node, shape.values[index], depth + 1);
            return null;
        }
        if (std.mem.eql(u8, shape.kind, "reference") and shape.name != null and shape.path == null) {
            if (contains(node.parsed.value.root_writes, shape.name.?)) return null;
            for (node.parsed.value.imports) |record| {
                if (!std.mem.eql(u8, record.local, shape.name.?)) continue;
                var seen = std.ArrayList(Trail).empty;
                defer seen.deinit(self.allocator);
                const resolved = try self.resolveImportOrigin(node, record.source, record.imported, &seen);
                if (resolved != .found or resolved.found.node == null) return null;
                return self.knownString(resolved.found.node.?, .{ .kind = "reference", .name = resolved.found.name }, depth + 1);
            }
            for (node.parsed.value.bindings) |binding| if (std.mem.eql(u8, binding.name, shape.name.?)) return self.knownString(node, binding.shape, depth + 1);
        }
        return null;
    }

    fn knownTest(self: *Context, node: *Node, shape: ValueShape, nullish: bool, depth: usize) anyerror!?bool {
        if (depth >= 32) return null;
        if (contains(&.{ "record", "array", "function", "class" }, shape.kind)) return !nullish;
        if (std.mem.eql(u8, shape.kind, "undefined")) return nullish;
        if (std.mem.eql(u8, shape.kind, "primitive")) return if (nullish) shape.nullish orelse false else shape.truthy;
        if (std.mem.eql(u8, shape.kind, "parameter")) {
            if (try self.possibleDefault(node, shape)) return null;
            const value = self.parameterValue(node, shape) orelse return null;
            const previous = self.parameters;
            self.parameters = value.scope;
            defer self.parameters = previous;
            return self.knownTest(value.node, value.shape, nullish, depth + 1);
        }
        if (std.mem.eql(u8, shape.kind, "reference") and shape.name != null and shape.path == null) {
            for (node.parsed.value.imports) |record| {
                if (!std.mem.eql(u8, record.local, shape.name.?)) continue;
                var seen = std.ArrayList(Trail).empty;
                defer seen.deinit(self.allocator);
                const resolved = try self.resolveImportOrigin(node, record.source, record.imported, &seen);
                if (resolved != .found or resolved.found.node == null) return null;
                return self.knownTest(resolved.found.node.?, .{ .kind = "reference", .name = resolved.found.name }, nullish, depth + 1);
            }
            for (node.parsed.value.bindings) |binding| if (std.mem.eql(u8, binding.name, shape.name.?) and !contains(node.parsed.value.root_writes, binding.name)) return self.knownTest(node, binding.shape, nullish, depth + 1);
        }
        if (std.mem.eql(u8, shape.kind, "call") and shape.factory != null and shape.values.len > 0) {
            if (try self.factory(node, shape.factory.?, 0)) |contract| {
                if (std.mem.eql(u8, contract, "observable")) return !nullish;
                return self.knownTest(node, shape.values[0], nullish, depth + 1);
            }
        }
        if (try self.branchChoice(node, shape, depth + 1)) |index| return self.knownTest(node, shape.values[index], nullish, depth + 1);
        return null;
    }

    fn branchChoice(self: *Context, node: *Node, shape: ValueShape, depth: usize) anyerror!?usize {
        if (depth >= 32) return null;
        if (std.mem.eql(u8, shape.kind, "sequence")) return if (shape.values.len > 0) @as(usize, 0) else null;
        if (std.mem.eql(u8, shape.kind, "conditional") and shape.values.len == 3) {
            const condition = (try self.knownTest(node, shape.values[0], false, depth + 1)) orelse return null;
            return if (condition) @as(usize, 1) else @as(usize, 2);
        }
        if (std.mem.eql(u8, shape.kind, "logical") and shape.values.len == 2 and shape.name != null) {
            const condition = (try self.knownTest(node, shape.values[0], std.mem.eql(u8, shape.name.?, "??"), depth + 1)) orelse return null;
            return if (std.mem.eql(u8, shape.name.?, "||")) (if (condition) @as(usize, 0) else @as(usize, 1)) else (if (condition) @as(usize, 1) else @as(usize, 0));
        }
        return null;
    }

    fn resultCoerces(self: *Context, node: *Node, shape: ValueShape, access: Access, depth: usize) anyerror!bool {
        if (depth >= 32 or shape.kind.len == 0) {
            const label = try std.fmt.allocPrint(self.allocator, "template result -> {s}", .{access.name});
            defer self.allocator.free(label);
            try self.labels.append(self.allocator, label);
            defer _ = self.labels.pop();
            try self.warning(false, if (depth >= 32) "template result conversion reached the analysis limit; simplify the expression or expose supported observable data" else "template result conversion provenance is unresolved; expose supported observable data");
            return false;
        }
        if (std.mem.eql(u8, shape.kind, "reference")) return shape.name != null and std.mem.eql(u8, shape.name.?, access.name) and samePath(shape.path, access.path);
        if (try self.branchChoice(node, shape, depth + 1)) |index| return self.resultCoerces(node, shape.values[index], access, depth + 1);
        if (std.mem.eql(u8, shape.kind, "logical") or std.mem.eql(u8, shape.kind, "conditional")) {
            const start: usize = if (std.mem.eql(u8, shape.kind, "conditional")) 1 else 0;
            for (shape.values[start..]) |value| if (try self.resultCoerces(node, value, access, depth + 1)) return true;
        }
        return false;
    }

    fn arrayBinding(self: *Context, node: *Node, name: []const u8, method: []const u8, depth: usize) anyerror!bool {
        if (depth >= 32 or contains(node.parsed.value.root_writes, name)) return false;
        for (node.parsed.value.assignments) |assignment| {
            if (!std.mem.eql(u8, assignment.target, name)) continue;
            if (contains(&.{ "push", "unshift", "splice", "fill" }, assignment.operator)) continue;
            if (assignment.dynamic_path or assignment.path == null or std.mem.eql(u8, assignment.path.?, method) or std.mem.startsWith(u8, assignment.path.?, "constructor")) return false;
        }
        for (node.parsed.value.imports) |record| {
            if (!std.mem.eql(u8, record.local, name)) continue;
            var seen = std.ArrayList(Trail).empty;
            defer seen.deinit(self.allocator);
            const resolved = try self.resolveImportOrigin(node, record.source, record.imported, &seen);
            if (resolved != .found or resolved.found.node == null) return false;
            return self.arrayBinding(resolved.found.node.?, resolved.found.name, method, depth + 1);
        }
        for (node.parsed.value.bindings) |binding| {
            if (!std.mem.eql(u8, binding.name, name)) continue;
            var shape = binding.shape;
            if (std.mem.eql(u8, shape.kind, "call") and shape.native_callee and shape.callee != null and std.mem.eql(u8, shape.callee.?, "Object.keys") and !hasLocal(node, "Object")) return true;
            if (std.mem.eql(u8, shape.kind, "call")) {
                const factory_name = shape.factory orelse return false;
                if (try self.factory(node, factory_name, 0) == null or shape.values.len == 0) return false;
                shape = shape.values[0];
            }
            if (std.mem.eql(u8, shape.kind, "array")) return true;
            if (std.mem.eql(u8, shape.kind, "reference") and shape.path == null and shape.name != null) return self.arrayBinding(node, shape.name.?, method, depth + 1);
            return false;
        }
        return false;
    }

    fn retainedCalls(self: *Context, node: *Node, factories: []const []const u8) anyerror!void {
        for (factories) |factory_name| {
            if (try self.factory(node, factory_name, 0)) |_| continue;
            try self.labels.append(self.allocator, factory_name);
            defer _ = self.labels.pop();
            try self.warning(false, "helper closures retain a local call result whose ownership is unverified; create observable state inside the helper");
        }
    }

    fn projectedResults(self: *Context, node: *Node, projections: []const []const u8) anyerror!void {
        for (projections) |projection| {
            if (std.mem.indexOf(u8, projection, "().")) |result_at| {
                const callee = projection[0..result_at];
                const member = projection[result_at + 3 ..];
                if (std.mem.indexOfScalar(u8, callee, '.')) |dot| {
                    const method = callee[dot + 1 ..];
                    if (contains(&.{ "map", "filter", "slice", "flat", "flatMap", "concat", "toReversed", "toSorted", "toSpliced", "with" }, method) and contains(&.{ "length", "map", "filter", "reduce", "reduceRight", "join", "slice", "includes", "some", "every", "toString" }, member) and try self.arrayBinding(node, callee[0..dot], method, 0)) continue;
                }
            }
            try self.labels.append(self.allocator, projection);
            defer _ = self.labels.pop();
            try self.warning(false, "helper return-value projection has unverified callable and retained-alias coverage; expose observable plain data");
        }
    }

    fn renderAccess(self: *Context, entry: *Node, name: []const u8, path: ?[]const u8, invoking: bool) anyerror!void {
        if (!hasLocal(entry, name)) {
            if (knownGlobal(name)) return;
            return self.globalWarning(name, path);
        }
        self.render_binding = name;
        self.invoking = invoking;
        try self.trace(entry, name, path, false);
    }

    fn loopAccess(self: *Context, entry: *Node, name: []const u8, path: ?[]const u8, invoking: bool, available: usize) anyerror!void {
        var index = available;
        while (index > 0) {
            index -= 1;
            const origin = self.loop_origins.items[index];
            if (!std.mem.eql(u8, origin.name, name)) continue;
            try self.labels.append(self.allocator, origin.expression);
            defer _ = self.labels.pop();
            const source = try std.fmt.allocPrint(self.allocator, "const __loop = () => ({s});", .{origin.expression});
            defer self.allocator.free(source);
            const raw = try backend.analyzeModuleStateRaw(source, "loop.ts", self.allocator);
            defer self.allocator.free(raw);
            const parsed = try std.json.parseFromSlice(Facts, self.allocator, raw, .{ .ignore_unknown_fields = true });
            defer parsed.deinit();
            if (!parsed.value.ok or parsed.value.bindings.len == 0) return self.warning(false, "loop element provenance could not be analyzed");
            const accesses = parsed.value.bindings[0].accesses;
            if (accesses.len != 1 or accesses[0].call) return self.warning(false, "loop element comes from an unverified iterable projection; expose observable plain data");
            const access = accesses[0];
            const combined = try std.fmt.allocPrint(self.allocator, "{s}{s}[computed]{s}{s}", .{ access.path orelse "", if (access.path != null) "." else "", if (path != null) "." else "", path orelse "" });
            defer self.allocator.free(combined);
            var outer = false;
            for (self.loop_origins.items[0..index]) |previous| if (std.mem.eql(u8, previous.name, access.name)) {
                outer = true;
            };
            if (outer) try self.loopAccess(entry, access.name, combined, invoking, index) else try self.renderAccess(entry, access.name, combined, invoking);
            return;
        }
    }

    fn warning(self: *Context, raw: bool, reason: []const u8) !void {
        const chain = try std.mem.join(self.allocator, " -> ", self.labels.items);
        defer self.allocator.free(chain);
        const code = if (raw) "reactivity.untracked_external_state" else "reactivity.unverified_dependency";
        const key = try std.fmt.allocPrint(self.allocator, "{s}:{s}", .{ code, chain });
        if (self.emitted.contains(key)) {
            self.allocator.free(key);
            return;
        }
        self.emitted.put(key, {}) catch |err| {
            self.allocator.free(key);
            return err;
        };
        const message = try std.fmt.allocPrint(self.allocator, "{s}: {s}. Dependency: {s}. Use an explicit observable or subscription adapter.{s}", .{
            if (raw) "Changes to this external value are not automatically tracked" else "Weiv cannot verify reactive updates for this dependency",                          reason, chain,
            if (self.plan == null) " Automatic wrapping requires a managed-module build." else " This dependency crosses an unverified ownership or notification boundary.",
        });
        defer self.allocator.free(message);
        try self.bag.appendOwned(self.allocator, code, .warning, message, .binding, self.model.source_path, self.use_span, diagnostics.computeLocation(self.model.source, self.use_span), false);
    }

    fn globalWarning(self: *Context, name: []const u8, path: ?[]const u8) !void {
        const label = try std.fmt.allocPrint(self.allocator, "global::{s}{s}{s}", .{ name, if (path != null) "." else "", path orelse "" });
        defer self.allocator.free(label);
        try self.labels.append(self.allocator, label);
        defer _ = self.labels.pop();
        try self.warning(false, "global value has no verified notification contract");
    }

    fn trace(self: *Context, node: *Node, name: []const u8, path: ?[]const u8, exported: bool) anyerror!void {
        const label = try std.fmt.allocPrint(self.allocator, "{s}::{s}{s}{s}", .{ node.path, name, if (path != null) "." else "", path orelse "" });
        defer self.allocator.free(label);
        const repeated = self.labels.items.len > 0 and std.mem.eql(u8, self.labels.items[self.labels.items.len - 1], label);
        if (!repeated) try self.labels.append(self.allocator, label);
        defer if (!repeated) {
            _ = self.labels.pop();
        };
        for (self.trail.items) |previous| {
            if (previous.node == node and previous.exported == exported and std.mem.eql(u8, previous.name, name)) {
                try self.warning(false, "cyclic dependency coverage is unresolved");
                return;
            }
        }
        if (self.trail.items.len >= 64) {
            try self.warning(false, "dependency analysis depth limit reached");
            return;
        }
        try self.trail.append(self.allocator, .{ .node = node, .name = name, .exported = exported });
        defer _ = self.trail.pop();
        if (!node.parsed.value.ok) {
            try self.warning(false, "module analysis failed");
            return;
        }
        if (exported) return self.traceExport(node, name, path);
        if (node.component and std.mem.eql(u8, name, "props")) return; // Framework input protocol.
        for (node.parsed.value.imports) |import| {
            if (!std.mem.eql(u8, import.local, name)) continue;
            if (node.component and !self.owning_only) if (self.plan) |plan| try plan.watchImported(self.allocator, self.model.source_path, name, self.render_binding, false);
            if (node.component) try self.traceIncomingWithFlows(node, name, path, false);
            return self.traceImport(node, import.source, import.imported, path);
        }
        for (node.parsed.value.bindings) |binding| {
            if (!std.mem.eql(u8, binding.name, name)) continue;
            const kind = binding.value_kind;
            const opaque_source = self.owning_only and std.mem.eql(u8, kind, "unknown") and binding.shape.kind.len == 0;
            if (opaque_source and path != null) try self.warning(false, "execution object remains raw; values returned by its methods may retain untracked aliases. Expose observable data or use an adapter");
            if (node.component and !opaque_source) if (self.plan) |plan| {
                if (self.owning_only) try plan.selectLocal(self.allocator, self.model.source_path, name) else try plan.watchLocal(self.allocator, self.model.source_path, name, self.render_binding);
            };
            try self.traceIncoming(node, name, path);
            if (std.mem.eql(u8, kind, "function") and self.coercing != 0 and !self.invoking) {
                if (self.coercing & 8 != 0) {
                    var unverified = contains(node.parsed.value.root_writes, name) or (!node.component and !self.owns(node));
                    for (node.parsed.value.assignments) |assignment| if (std.mem.eql(u8, assignment.target, name)) {
                        unverified = true;
                    };
                    if (unverified) try self.warning(false, "callable serialization properties are outside the plain-data tracking contract; serialize plain data instead");
                } else try self.warning(false, "callable conversion properties are outside the plain-data tracking contract; render supported plain data");
                return;
            }
            if (std.mem.eql(u8, kind, "class") or (std.mem.eql(u8, kind, "function") and path != null)) {
                try self.warning(false, "class state and function properties are outside the plain-data tracking contract");
                return;
            }
            if (std.mem.eql(u8, kind, "function") and contains(node.parsed.value.root_writes, name) and
                (!std.mem.eql(u8, binding.declaration_kind, "let") and !std.mem.eql(u8, binding.declaration_kind, "const")))
            {
                try self.warning(false, "reassigned function binding has no verified cell subscription path; put the callable in observable data");
            }
            const stable = !contains(node.parsed.value.root_writes, name) and (std.mem.eql(u8, binding.declaration_kind, "const") or !node.parsed.value.dynamic_access);
            const managed = self.owns(node);
            const selected = managed and !std.mem.eql(u8, name, "<default>") and
                (std.mem.eql(u8, binding.declaration_kind, "let") or std.mem.eql(u8, binding.declaration_kind, "const")) and
                !node.parsed.value.dynamic_access and !opaque_source;
            if (selected) {
                if (self.plan) |plan| {
                    if (self.owning_only) try plan.normalize(self.allocator, node.path, name, self.model.source_path) else try plan.select(self.allocator, node.path, name, self.model.source_path, self.render_binding);
                }
            }
            const previous_ownership = self.owning_only;
            if (std.mem.eql(u8, kind, "function")) self.owning_only = false else if (node.component or selected) self.owning_only = true;
            defer self.owning_only = previous_ownership;
            if ((node.component or selected) and std.mem.eql(u8, kind, "destructured")) {
                try self.ownShape(node, binding.shape, 0);
                if (binding.shape.kind.len == 0) try self.warning(false, "destructured value provenance is unverified; expose observable data or a stable source");
                return self.inspectShape(node, binding.shape, path, false, 0);
            }
            if (std.mem.eql(u8, kind, "observable") or std.mem.eql(u8, kind, "snapshot")) {
                try self.inspectShape(node, binding.shape, path, std.mem.eql(u8, kind, "snapshot"), 0);
                if (stable) {
                    if (!selected and !self.owning_only and std.mem.eql(u8, kind, "observable") and self.indirect > 0) try self.warning(false, "observable dependency has no direct component subscription path");
                    return;
                }
            }
            if (std.mem.eql(u8, kind, "call")) if (binding.factory) |factory_name| {
                if (try self.factory(node, factory_name, 0)) |contract| {
                    try self.inspectShape(node, binding.shape, path, std.mem.eql(u8, contract, "snapshot"), 0);
                    if (stable) {
                        if (!selected and !self.owning_only and std.mem.eql(u8, contract, "observable") and self.indirect > 0) try self.warning(false, "observable dependency has no direct component subscription path");
                        return;
                    }
                }
            };
            if (std.mem.eql(u8, kind, "call") and path != null) if (binding.factory) |factory_name| {
                if (try self.inspectCallReturn(node, factory_name, path, false, 0, .{ .node = node, .values = binding.shape.values, .expanded = binding.shape.arguments_expanded })) return;
                const result_label = try std.fmt.allocPrint(self.allocator, "{s}() result", .{factory_name});
                defer self.allocator.free(result_label);
                try self.labels.append(self.allocator, result_label);
                defer _ = self.labels.pop();
                try self.warning(false, "helper result path has unverified return-value provenance; expose observable plain data");
            };
            if (std.mem.eql(u8, kind, "alias") and stable) {
                if (node.component or selected) {
                    try self.ownShape(node, binding.shape, 0);
                    return self.inspectShape(node, binding.shape, path, false, 0);
                }
                if (binding.alias) |alias| return self.trace(node, alias, path, false);
            }
            if (!node.component) {
                if (std.mem.eql(u8, kind, "primitive") and std.mem.eql(u8, binding.declaration_kind, "const") and stable) return;
                if (!selected and (std.mem.eql(u8, kind, "object") or std.mem.eql(u8, kind, "array") or std.mem.eql(u8, binding.declaration_kind, "let") or std.mem.eql(u8, binding.declaration_kind, "var"))) {
                    try self.warning(true, "module state has no observable notification contract");
                    return;
                }
            }
            if ((node.component or selected) and contains(&.{ "logical", "conditional", "sequence" }, binding.shape.kind)) {
                try self.ownShape(node, binding.shape, 0);
                return self.inspectShape(node, binding.shape, path, false, 0);
            }
            if ((node.component or selected) and (std.mem.eql(u8, kind, "object") or std.mem.eql(u8, kind, "array"))) {
                try self.ownShape(node, binding.shape, 0);
                return self.inspectShape(node, binding.shape, path, false, 0);
            }
            if (std.mem.eql(u8, kind, "function") or node.component or selected) {
                const indirect = !node.component and std.mem.eql(u8, kind, "function");
                if (indirect) self.indirect += 1;
                defer if (indirect) {
                    self.indirect -= 1;
                };
                try self.inspectEffects(node, binding.effects, false);
                // Raw/unknown arguments to ordinary library calls still cross a
                // boundary. An explicit observable/snapshot above is the contract.
                for (binding.accesses) |access| {
                    const previous_coercion = self.coercing;
                    self.coercing = coerces(node, binding.coercions, access);
                    defer self.coercing = previous_coercion;
                    const previous_invoking = self.invoking;
                    self.invoking = access.call;
                    defer self.invoking = previous_invoking;
                    if (std.mem.eql(u8, access.name, name)) {
                        if (std.mem.eql(u8, kind, "function") and access.path != null) try self.warning(false, "function properties are outside the observable data contract");
                        continue;
                    }
                    if (hasLocal(node, access.name)) {
                        try self.trace(node, access.name, access.path, false);
                    } else if (!knownGlobal(access.name) and !(node.component and std.mem.eql(u8, access.name, "emit"))) {
                        try self.globalWarning(access.name, access.path);
                    }
                }
                for (binding.globals) |global| {
                    if (knownGlobal(global) or (node.component and std.mem.eql(u8, global, "emit"))) continue;
                    var covered = false;
                    for (binding.accesses) |access| if (std.mem.eql(u8, access.name, global)) {
                        covered = true;
                    };
                    if (!covered) try self.globalWarning(global, null);
                }
                try self.projectedResults(node, binding.result_projections);
                try self.retainedCalls(node, binding.retained_local_calls);
                if (binding.retained_local_state) try self.warning(false, "helper closures retain raw local state outside declaration lowering; create observable state inside the helper");
                if (!node.component and binding.has_mutation) try self.warning(false, "helper contains mutations; purity is not established");
                for (binding.calls) |call| {
                    if (std.mem.eql(u8, call, "<dynamic>")) try self.warning(false, "helper invokes a dynamically selected function") else if (std.mem.indexOfScalar(u8, call, '.')) |dot| {
                        const root = call[0..dot];
                        if (!hasLocal(node, root) and (!knownGlobal(root) or !knownIntrinsicCall(call))) try self.warning(false, "helper invokes an opaque receiver method");
                    } else if (!hasLocal(node, call) and !knownGlobal(call)) try self.warning(false, "helper invokes an opaque callback");
                }
                return;
            }
            try self.warning(false, "exported value has unknown provenance");
            return;
        }
        try self.warning(false, "binding implementation is unavailable");
    }

    fn traceInvocation(self: *Context, node: *Node, effects: ValueShape) anyerror!void {
        // Immediate calls are effects; their results are not the caller's spread
        // result. Returned values enter expansion through the return facts.
        const previous_result = self.spread_result;
        const previous_proven = self.spread_proven;
        self.spread_result = null;
        self.spread_proven = null;
        defer self.spread_result = previous_result;
        defer self.spread_proven = previous_proven;
        try self.projectedResults(node, effects.result_projections);
        try self.inspectEffects(node, effects.effects, false);
        for (effects.accesses) |access| {
            const previous_coercion = self.coercing;
            self.coercing = coerces(node, effects.coercions, access);
            defer self.coercing = previous_coercion;
            const previous = self.invoking;
            self.invoking = access.call;
            defer self.invoking = previous;
            if (hasLocal(node, access.name)) try self.trace(node, access.name, access.path, false) else if (!knownGlobal(access.name)) try self.globalWarning(access.name, access.path);
        }
        for (effects.globals) |global| {
            if (!knownGlobal(global) and !hasLocal(node, global) and !(std.mem.eql(u8, global, "this") and self.hasOwnedReceiver(node, effects.scope_id))) try self.globalWarning(global, null);
        }
        for (effects.calls) |call| {
            var contextual = false;
            for (effects.effects) |effect| if (effect.hint == 0 and effect.value.name != null and std.mem.eql(u8, effect.value.name.?, call)) {
                contextual = true;
            };
            if (contextual) continue;
            if (std.mem.eql(u8, call, "<dynamic>")) try self.warning(false, "helper initialization invokes an unresolved function") else if (std.mem.indexOfScalar(u8, call, '.')) |dot| {
                if (!hasLocal(node, call[0..dot]) and !knownIntrinsicCall(call)) try self.warning(false, "helper initialization invokes an opaque receiver method");
            } else if (!hasLocal(node, call) and !knownGlobal(call)) try self.warning(false, "helper initialization invokes an opaque callback");
        }
    }

    fn namespaceRoot(self: *Context, node: *Node, name: []const u8, depth: usize) anyerror!ExportResolution {
        if (depth >= 32) return .unknown;
        var seen = std.ArrayList(Trail).empty;
        defer seen.deinit(self.allocator);
        const resolved = try self.resolveLocalOrigin(node, name, &seen);
        if (resolved != .found or resolved.found.node == null or std.mem.eql(u8, resolved.found.name, "*namespace*")) return resolved;
        for (resolved.found.node.?.parsed.value.bindings) |binding| {
            if (std.mem.eql(u8, binding.name, resolved.found.name) and std.mem.eql(u8, binding.value_kind, "alias") and binding.alias != null and !contains(resolved.found.node.?.parsed.value.root_writes, binding.name)) return self.namespaceRoot(resolved.found.node.?, binding.alias.?, depth + 1);
        }
        return resolved;
    }

    fn inspectCallReturn(self: *Context, node: *Node, name: []const u8, path: ?[]const u8, immutable: bool, depth: usize, arguments: CallArguments) anyerror!bool {
        if (depth >= 32) {
            try self.warning(false, "helper return analysis reached an unresolved cycle or depth limit");
            return true;
        }
        if (std.mem.indexOfScalar(u8, name, '.')) |dot| {
            var resolved = try self.namespaceRoot(node, name[0..dot], 0);
            var parts = std.mem.splitScalar(u8, name[dot + 1 ..], '.');
            while (parts.next()) |part| {
                if (resolved != .found or resolved.found.node == null or !std.mem.eql(u8, resolved.found.name, "*namespace*")) return false;
                var seen = std.ArrayList(Trail).empty;
                defer seen.deinit(self.allocator);
                resolved = try self.resolveExport(resolved.found.node.?, part, &seen);
            }
            if (resolved != .found or resolved.found.node == null) return false;
            return self.inspectCallReturn(resolved.found.node.?, resolved.found.name, path, immutable, depth + 1, arguments);
        }
        for (node.parsed.value.imports) |record| {
            if (!std.mem.eql(u8, record.local, name)) continue;
            var seen = std.ArrayList(Trail).empty;
            defer seen.deinit(self.allocator);
            const resolved = try self.resolveImportOrigin(node, record.source, record.imported, &seen);
            if (resolved != .found or resolved.found.node == null) return false;
            return self.inspectCallReturn(resolved.found.node.?, resolved.found.name, path, immutable, depth + 1, arguments);
        }
        for (node.parsed.value.bindings) |binding| {
            if (!std.mem.eql(u8, binding.name, name)) continue;
            if (contains(node.parsed.value.root_writes, name)) return false;
            if (std.mem.eql(u8, binding.value_kind, "alias") and binding.alias != null) return self.inspectCallReturn(node, binding.alias.?, path, immutable, depth + 1, arguments);
            if (binding.shape.async_result or binding.shape.generator_result) {
                try self.warning(false, "helper returns a Promise or iterator outside the plain-data tracking contract; resolve it into observable data through an explicit integration boundary");
                return true;
            }
            if (!std.mem.eql(u8, binding.shape.kind, "function") or binding.shape.returns.len == 0) return false;
            if (!node.component) self.indirect += 1;
            defer if (!node.component) {
                self.indirect -= 1;
            };
            const label = try std.fmt.allocPrint(self.allocator, "{s}::{s}()", .{ node.path, name });
            defer self.allocator.free(label);
            try self.labels.append(self.allocator, label);
            defer _ = self.labels.pop();
            var snapshots = true;
            for (binding.shape.returns) |returned| {
                if (!std.mem.eql(u8, returned.kind, "call") or returned.factory == null) {
                    snapshots = false;
                    break;
                }
                const contract = try self.factory(node, returned.factory.?, 0);
                if (contract == null or !std.mem.eql(u8, contract.?, "snapshot")) {
                    snapshots = false;
                    break;
                }
            }
            // Immediate effects belong to this invocation's parameter frame too;
            // native argument conversion may read a supplied argument's hooks.
            const parameters = ParameterScope{ .caller = arguments.node, .values = arguments.values, .expanded = arguments.expanded, .parent = self.parameters, .owner = binding.shape.scope_id, .owner_node = node };
            self.parameters = &parameters;
            defer self.parameters = parameters.parent;
            if (!immutable and !snapshots) {
                try self.retainedCalls(node, binding.retained_local_calls);
                if (binding.retained_local_state) try self.warning(false, "helper closures retain raw local state outside declaration lowering; create observable state inside the helper");
                if (binding.shape.invocation) |effects| try self.traceInvocation(node, effects.*);
            }
            const previous = self.inspecting_return;
            self.inspecting_return = true;
            defer self.inspecting_return = previous;
            for (binding.shape.returns) |returned| {
                if (!immutable) try self.ownShape(node, returned, depth + 1);
                try self.inspectShape(node, returned, path, immutable, depth + 1);
            }
            return true;
        }
        return false;
    }

    fn plainImmutableShape(shape: ValueShape, depth: usize) bool {
        if (depth >= 32) return false;
        if (std.mem.eql(u8, shape.kind, "primitive") or std.mem.eql(u8, shape.kind, "undefined")) return true;
        if (std.mem.eql(u8, shape.kind, "record")) {
            for (shape.properties) |property| if (property.name == null or !plainImmutableShape(property.value, depth + 1)) return false;
            return true;
        }
        if (std.mem.eql(u8, shape.kind, "array")) {
            for (shape.values) |value| if (!plainImmutableShape(value, depth + 1)) return false;
            return true;
        }
        return false;
    }

    fn plainTrackedShape(self: *Context, node: *Node, shape: ValueShape, depth: usize) anyerror!bool {
        if (depth >= 32) return false;
        if (std.mem.eql(u8, shape.kind, "primitive") or std.mem.eql(u8, shape.kind, "undefined")) return true;
        if (std.mem.eql(u8, shape.kind, "array")) {
            for (shape.values) |value| if (!try self.plainTrackedShape(node, value, depth + 1)) return false;
            return true;
        }
        if (std.mem.eql(u8, shape.kind, "record")) {
            for (shape.properties) |property| if (property.name == null or !try self.plainTrackedShape(node, property.value, depth + 1)) return false;
            return true;
        }
        if (std.mem.eql(u8, shape.kind, "call") and shape.factory != null and shape.values.len > 0) {
            if (try self.factory(node, shape.factory.?, 0)) |_| return self.plainTrackedShape(node, shape.values[0], depth + 1);
        }
        if (std.mem.eql(u8, shape.kind, "reference") and shape.name != null and shape.path == null) {
            for (node.parsed.value.bindings) |binding| {
                if (!std.mem.eql(u8, binding.name, shape.name.?) or contains(node.parsed.value.root_writes, binding.name)) continue;
                for (node.parsed.value.assignments) |assignment| {
                    if (std.mem.eql(u8, assignment.target, binding.name) and !try self.plainTrackedShape(node, assignment.value.shape, depth + 1)) return false;
                }
                return self.plainTrackedShape(node, binding.shape, depth + 1);
            }
        }
        return false;
    }

    fn ownDataPath(self: *Context, node: *Node, shape: ValueShape, path: []const u8, depth: usize) anyerror!bool {
        if (depth >= 32) return false;
        if (std.mem.eql(u8, shape.kind, "parameter")) {
            if (try self.possibleDefault(node, shape) and !try self.ownDataPath(node, shape.values[0], path, depth + 1)) return false;
            const value = self.parameterValue(node, shape) orelse return false;
            const previous = self.parameters;
            self.parameters = value.scope;
            defer self.parameters = previous;
            return self.ownDataPath(value.node, value.shape, path, depth + 1);
        }
        if (std.mem.eql(u8, shape.kind, "reference") and shape.name != null and shape.path == null) {
            for (node.parsed.value.bindings) |binding| if (std.mem.eql(u8, binding.name, shape.name.?) and !contains(node.parsed.value.root_writes, binding.name)) return self.ownDataPath(node, binding.shape, path, depth + 1);
        }
        if (std.mem.eql(u8, shape.kind, "call") and shape.factory != null and shape.values.len > 0) {
            if (try self.factory(node, shape.factory.?, 0)) |_| return self.ownDataPath(node, shape.values[0], path, depth + 1);
        }
        if (path.len == 0) return self.plainTrackedShape(node, shape, depth + 1);
        const dot = std.mem.indexOfScalar(u8, path, '.') orelse path.len;
        const member = path[0..dot];
        const rest = if (dot < path.len) path[dot + 1 ..] else "";
        if (std.mem.eql(u8, shape.kind, "record")) {
            var index = shape.properties.len;
            while (index > 0) {
                index -= 1;
                const property = shape.properties[index];
                if (property.name == null) return false;
                if (std.mem.eql(u8, property.name.?, member)) return self.ownDataPath(node, property.value, rest, depth + 1);
            }
        }
        if (std.mem.eql(u8, shape.kind, "array")) {
            const index = std.fmt.parseInt(usize, member, 10) catch return false;
            if (index < shape.values.len) return self.ownDataPath(node, shape.values[index], rest, depth + 1);
        }
        return false;
    }

    fn captureSubscription(self: *Context, node: *Node, shape: ValueShape, depth: usize) anyerror!bool {
        if (depth >= 32) return false;
        if (std.mem.eql(u8, shape.kind, "parameter")) {
            if (shape.rest_parameter or try self.possibleDefault(node, shape)) return false;
            const value = self.parameterValue(node, shape) orelse return false;
            const previous = self.parameters;
            self.parameters = value.scope;
            defer self.parameters = previous;
            return self.captureSubscription(value.node, value.shape, depth + 1);
        }
        if (!std.mem.eql(u8, shape.kind, "reference") or shape.name == null or shape.path != null) return false;
        const name = shape.name.?;
        for (node.parsed.value.imports) |record| {
            if (!std.mem.eql(u8, record.local, name)) continue;
            var seen = std.ArrayList(Trail).empty;
            defer seen.deinit(self.allocator);
            const resolved = try self.resolveImportOrigin(node, record.source, record.imported, &seen);
            if (resolved != .found or resolved.found.node == null) return false;
            return self.captureSubscription(resolved.found.node.?, .{ .kind = "reference", .name = resolved.found.name }, depth + 1);
        }
        if (!node.component and !self.owns(node)) return false;
        for (node.parsed.value.bindings) |binding| {
            if (!std.mem.eql(u8, binding.name, name)) continue;
            if (contains(node.parsed.value.root_writes, name) or (!std.mem.eql(u8, binding.declaration_kind, "let") and !std.mem.eql(u8, binding.declaration_kind, "const")) or std.mem.eql(u8, binding.value_kind, "function") or std.mem.eql(u8, binding.value_kind, "class")) return false;
            if (!try self.plainTrackedShape(node, .{ .kind = "reference", .name = name }, depth + 1)) return false;
            const invoking = self.invoking;
            self.invoking = false;
            defer self.invoking = invoking;
            try self.trace(node, name, null, false);
            return true;
        }
        return false;
    }

    fn definitelyDefined(self: *Context, node: *Node, shape: ValueShape, depth: usize) anyerror!bool {
        if (depth >= 32) return false;
        if (contains(&.{ "primitive", "record", "array", "function", "class" }, shape.kind)) return true;
        if (std.mem.eql(u8, shape.kind, "parameter")) {
            const value = self.parameterValue(node, shape) orelse return false;
            const previous = self.parameters;
            self.parameters = value.scope;
            defer self.parameters = previous;
            return self.definitelyDefined(value.node, value.shape, depth + 1);
        }
        if (std.mem.eql(u8, shape.kind, "call") and shape.factory != null and shape.values.len > 0) {
            if (try self.factory(node, shape.factory.?, 0)) |contract| {
                if (std.mem.eql(u8, contract, "observable")) return true;
                return self.definitelyDefined(node, shape.values[0], depth + 1);
            }
        }
        if (std.mem.eql(u8, shape.kind, "reference") and shape.name != null and shape.path == null) {
            for (node.parsed.value.imports) |record| {
                if (!std.mem.eql(u8, record.local, shape.name.?)) continue;
                var seen = std.ArrayList(Trail).empty;
                defer seen.deinit(self.allocator);
                const resolved = try self.resolveImportOrigin(node, record.source, record.imported, &seen);
                if (resolved != .found or resolved.found.node == null) return false;
                return self.definitelyDefined(resolved.found.node.?, .{ .kind = "reference", .name = resolved.found.name }, depth + 1);
            }
            for (node.parsed.value.bindings) |binding| if (std.mem.eql(u8, binding.name, shape.name.?) and !contains(node.parsed.value.root_writes, binding.name)) return self.definitelyDefined(node, binding.shape, depth + 1);
        }
        return false;
    }

    fn possibleDefault(self: *Context, node: *Node, shape: ValueShape) anyerror!bool {
        if (shape.values.len == 0 or shape.parameter_index == null or shape.rest_parameter) return false;
        const parameters = self.parameterFrame(node, shape) orelse return false;
        const index = shape.parameter_index.?;
        if (parameters.expanded or index >= parameters.values.len or std.mem.eql(u8, parameters.values[index].kind, "undefined")) return false;
        const previous = self.parameters;
        self.parameters = if (parameters.scoped_arguments) parameters.argument_scope else parameters.parent;
        defer self.parameters = previous;
        return !try self.definitelyDefined(parameters.caller, parameters.values[index], 0);
    }

    fn parameterFrame(self: *Context, node: *Node, shape: ValueShape) ?*const ParameterScope {
        var current = self.parameters;
        while (current) |parameters| : (current = parameters.parent) {
            if (shape.scope_id == null or (parameters.owner_node == node and parameters.owner == shape.scope_id)) return parameters;
        }
        return null;
    }

    fn hasOwnedReceiver(self: *Context, node: *Node, owner: ?u64) bool {
        if (owner == null) return false;
        const frame = self.parameterFrame(node, .{ .scope_id = owner }) orelse return false;
        return frame.receiver != null;
    }

    fn parameterValue(self: *Context, node: *Node, shape: ValueShape) ?ParameterValue {
        const parameters = self.parameterFrame(node, shape) orelse return null;
        if (parameters.expanded or shape.parameter_index == null) return null;
        const argument_scope = if (parameters.scoped_arguments) parameters.argument_scope else parameters.parent;
        const index = shape.parameter_index.?;
        if (shape.rest_parameter) return .{ .node = parameters.caller, .shape = .{ .kind = "array", .values = if (index < parameters.values.len) parameters.values[index..] else &.{} }, .scope = argument_scope };
        if (index >= parameters.values.len or std.mem.eql(u8, parameters.values[index].kind, "undefined")) {
            return .{ .node = node, .shape = if (shape.values.len > 0) shape.values[0] else .{ .kind = "undefined" }, .scope = parameters };
        }
        return .{ .node = parameters.caller, .shape = parameters.values[index], .scope = argument_scope };
    }

    fn passiveCapture(self: *Context, node: *Node, shape: ValueShape, depth: usize) anyerror!bool {
        if (depth >= 32) return false;
        if (std.mem.eql(u8, shape.kind, "parameter")) {
            if (shape.rest_parameter) return false;
            if (try self.possibleDefault(node, shape) and !try self.passiveCapture(node, shape.values[0], depth + 1)) return false;
            const value = self.parameterValue(node, shape) orelse return false;
            const previous = self.parameters;
            self.parameters = value.scope;
            defer self.parameters = previous;
            return self.passiveCapture(value.node, value.shape, depth + 1);
        }
        if (std.mem.eql(u8, shape.kind, "primitive") or std.mem.eql(u8, shape.kind, "undefined")) return true;
        if (!std.mem.eql(u8, shape.kind, "call") or shape.factory == null or shape.values.len == 0) return false;
        const contract = try self.factory(node, shape.factory.?, 0);
        return contract != null and std.mem.eql(u8, contract.?, "snapshot") and plainImmutableShape(shape.values[0], 0);
    }

    fn inspectJson(self: *Context, node: *Node, shape: ValueShape, key: []const u8, immutable: bool, depth: usize, skip_hook: bool) anyerror!void {
        if (depth >= 48) {
            try self.warning(false, "JSON serialization analysis reached an unresolved cycle or limit; serialize supported plain data");
            return;
        }
        if (contains(&.{ "primitive", "undefined" }, shape.kind)) return;
        if (std.mem.eql(u8, shape.kind, "function")) return; // Fresh callable literals have no own serialization hook.
        if (std.mem.eql(u8, shape.kind, "record")) {
            var hook: ?ValueShape = null;
            var index = shape.properties.len;
            while (index > 0) {
                index -= 1;
                const property = shape.properties[index];
                if (property.name == null) {
                    try self.warning(false, "computed JSON keys may define an unverified serialization hook");
                    continue;
                }
                if (std.mem.eql(u8, property.name.?, "__proto__")) try self.warning(false, "inherited JSON serialization hooks have unverified coverage");
                if (std.mem.eql(u8, property.name.?, "toJSON") and hook == null) hook = property.value;
            }
            if (!skip_hook) if (hook) |value| {
                if (!contains(&.{ "primitive", "undefined", "record", "array" }, value.kind)) {
                    if (try self.jsonHook(node, value, .{ .node = node, .shape = shape, .scope = self.parameters }, key, immutable, depth + 1)) return;
                    try self.warning(false, "JSON serialization hook implementation or subscription path is unverified; serialize observable plain data or use an adapter");
                    return;
                }
            };
            for (shape.properties) |property| {
                const name = property.name orelse continue;
                if (std.mem.eql(u8, property.value.kind, "function")) continue;
                const label = try std.fmt.allocPrint(self.allocator, "JSON field {s}", .{name});
                defer self.allocator.free(label);
                try self.labels.append(self.allocator, label);
                defer _ = self.labels.pop();
                const previous_key = self.json_key;
                self.json_key = name;
                defer self.json_key = previous_key;
                const previous_skip = self.json_skip_hook;
                self.json_skip_hook = false;
                defer self.json_skip_hook = previous_skip;
                const previous = self.coercing;
                self.coercing = 8;
                defer self.coercing = previous;
                try self.inspectShape(node, property.value, null, immutable, depth + 1);
            }
            return;
        }
        if (std.mem.eql(u8, shape.kind, "array")) {
            for (shape.values, 0..) |value, index| {
                const key_text = try std.fmt.allocPrint(self.allocator, "{d}", .{index});
                defer self.allocator.free(key_text);
                const previous_key = self.json_key;
                self.json_key = key_text;
                defer self.json_key = previous_key;
                const previous_skip = self.json_skip_hook;
                self.json_skip_hook = false;
                defer self.json_skip_hook = previous_skip;
                const previous = self.coercing;
                self.coercing = 8;
                defer self.coercing = previous;
                try self.inspectShape(node, value, null, immutable, depth + 1);
            }
            return;
        }
        try self.warning(false, "JSON value provenance may hide serialization callbacks; expose supported observable plain data");
    }

    fn jsonHook(self: *Context, node: *Node, shape: ValueShape, receiver: ParameterValue, key: []const u8, immutable: bool, depth: usize) anyerror!bool {
        if (depth >= 48) {
            try self.warning(false, "JSON callback provenance reached an unresolved cycle or limit");
            return true;
        }
        if (std.mem.eql(u8, shape.kind, "reference") and shape.name != null and shape.path == null) {
            for (node.parsed.value.imports) |record| {
                if (!std.mem.eql(u8, record.local, shape.name.?)) continue;
                var seen = std.ArrayList(Trail).empty;
                defer seen.deinit(self.allocator);
                const resolved = try self.resolveImportOrigin(node, record.source, record.imported, &seen);
                if (resolved != .found or resolved.found.node == null) return false;
                return self.jsonHook(resolved.found.node.?, .{ .kind = "reference", .name = resolved.found.name }, receiver, key, immutable, depth + 1);
            }
            for (node.parsed.value.bindings) |binding| if (std.mem.eql(u8, binding.name, shape.name.?) and !contains(node.parsed.value.root_writes, binding.name)) return self.jsonHook(node, binding.shape, receiver, key, immutable, depth + 1);
            return false;
        }
        if (!std.mem.eql(u8, shape.kind, "function")) return false;
        const label = "implicit toJSON()";
        try self.labels.append(self.allocator, label);
        defer _ = self.labels.pop();
        const previous_receiver = self.receiver;
        self.receiver = if (shape.lexical_this) null else receiver;
        defer self.receiver = previous_receiver;
        const arguments = [_]ValueShape{.{ .kind = "primitive", .truthy = key.len > 0 }};
        const parameters = ParameterScope{ .caller = node, .values = &arguments, .expanded = false, .parent = self.parameters, .owner = shape.scope_id, .owner_node = node, .receiver = self.receiver };
        self.parameters = &parameters;
        defer self.parameters = parameters.parent;
        const previous_coercion = self.coercing;
        const previous_invoking = self.invoking;
        const previous_shallow = self.shallow_invocation;
        self.coercing = 0;
        self.invoking = true;
        self.shallow_invocation = true;
        try self.inspectShape(node, shape, null, immutable, depth + 1);
        self.coercing = previous_coercion;
        self.invoking = previous_invoking;
        self.shallow_invocation = previous_shallow;
        if (shape.async_result or shape.generator_result) {
            try self.warning(false, "JSON hook returns a Promise or iterator outside the supported data contract");
            return true;
        }
        const previous_skip = self.json_skip_hook;
        self.json_skip_hook = true;
        defer self.json_skip_hook = previous_skip;
        const previous_return = self.inspecting_return;
        self.inspecting_return = true;
        defer self.inspecting_return = previous_return;
        for (shape.returns) |returned| try self.inspectShape(node, returned, null, immutable, depth + 1);
        return true;
    }

    fn primitiveHook(self: *Context, node: *Node, shape: ValueShape, depth: usize) anyerror!bool {
        if (depth >= 32) return false;
        if (std.mem.eql(u8, shape.kind, "function") and shape.returns.len > 0) {
            for (shape.returns) |returned| if (!contains(&.{ "primitive", "undefined" }, returned.kind)) return false;
            return true;
        }
        if (std.mem.eql(u8, shape.kind, "reference") and shape.name != null and shape.path == null) {
            for (node.parsed.value.imports) |record| {
                if (!std.mem.eql(u8, record.local, shape.name.?)) continue;
                var seen = std.ArrayList(Trail).empty;
                defer seen.deinit(self.allocator);
                const resolved = try self.resolveImportOrigin(node, record.source, record.imported, &seen);
                if (resolved != .found or resolved.found.node == null) return false;
                return self.primitiveHook(resolved.found.node.?, .{ .kind = "reference", .name = resolved.found.name }, depth + 1);
            }
            for (node.parsed.value.bindings) |binding| {
                if (std.mem.eql(u8, binding.name, shape.name.?) and !contains(node.parsed.value.root_writes, binding.name)) return self.primitiveHook(node, binding.shape, depth + 1);
            }
        }
        return false;
    }

    fn inspectConversion(self: *Context, node: *Node, shape: ValueShape, immutable: bool, depth: usize, numeric: bool) anyerror!void {
        const methods = if (numeric) [_][]const u8{ "valueOf", "toString" } else [_][]const u8{ "toString", "valueOf" };
        for (methods) |method| {
            var selected: ?ValueShape = null;
            var index = shape.properties.len;
            while (index > 0) {
                index -= 1;
                const property = shape.properties[index];
                if (property.name != null and std.mem.eql(u8, property.name.?, method)) {
                    selected = property.value;
                    break;
                }
            }
            if (selected) |value| {
                const previous = self.invoking;
                self.invoking = true;
                defer self.invoking = previous;
                const label = try std.fmt.allocPrint(self.allocator, "implicit {s}()", .{method});
                defer self.allocator.free(label);
                try self.labels.append(self.allocator, label);
                defer _ = self.labels.pop();
                try self.inspectShape(node, value, null, immutable, depth + 1);
                if (try self.primitiveHook(node, value, depth + 1)) return;
            } else if (std.mem.eql(u8, method, "toString")) return;
        }
    }

    fn inspectShape(self: *Context, node: *Node, shape: ValueShape, path: ?[]const u8, immutable: bool, depth: usize) anyerror!void {
        if (depth >= 64) return self.warning(false, "wrapped value provenance has an unresolved cycle or exceeds the analysis limit");
        if (std.mem.eql(u8, shape.kind, "local_reference")) return self.unknownProjection(path);
        if (std.mem.eql(u8, shape.kind, "receiver")) {
            const frame = if (shape.scope_id != null) self.parameterFrame(node, shape) else null;
            const receiver = (if (frame) |owner| owner.receiver else null) orelse {
                try self.warning(false, "callable receiver provenance is unverified; expose observable plain data");
                return;
            };
            const previous = self.parameters;
            self.parameters = receiver.scope;
            defer self.parameters = previous;
            try self.ownShape(receiver.node, receiver.shape, depth + 1);
            return self.inspectShape(receiver.node, receiver.shape, path, immutable, depth + 1);
        }
        if (std.mem.eql(u8, shape.kind, "parameter")) {
            if (try self.possibleDefault(node, shape)) try self.inspectShape(node, shape.values[0], path, immutable, depth + 1);
            const value = self.parameterValue(node, shape) orelse return self.unknownProjection(path);
            const previous = self.parameters;
            self.parameters = value.scope;
            defer self.parameters = previous;
            return self.inspectShape(value.node, value.shape, path, immutable, depth + 1);
        }
        if (contains(&.{ "logical", "conditional", "sequence" }, shape.kind)) {
            if (try self.branchChoice(node, shape, depth + 1)) |index| return self.inspectShape(node, shape.values[index], path, immutable, depth + 1);
            const start: usize = if (std.mem.eql(u8, shape.kind, "conditional")) 1 else 0;
            for (shape.values[start..]) |value| try self.inspectShape(node, value, path, immutable, depth + 1);
            return;
        }
        if (std.mem.eql(u8, shape.kind, "default")) {
            for (shape.values) |value| try self.inspectShape(node, value, path, immutable, depth + 1);
            return;
        }
        if (std.mem.eql(u8, shape.kind, "computed_projection")) {
            if (shape.values.len != 2) return self.unknownProjection(path);
            {
                const previous_call = self.converting_call;
                const previous_receiver = self.receiver;
                const previous_result = self.spread_result;
                const previous_proven = self.spread_proven;
                self.converting_call = null;
                self.receiver = null;
                self.spread_result = null;
                self.spread_proven = null;
                defer self.converting_call = previous_call;
                defer self.receiver = previous_receiver;
                defer self.spread_result = previous_result;
                defer self.spread_proven = previous_proven;
                try self.convertedResult(node, shape.values[1], 1, depth + 1, false);
            }
            const key = try self.knownString(node, shape.values[1], depth + 1) orelse return self.warning(false, "computed callable key or coercion is unverified; expose a stable string key or use an adapter");
            if (std.mem.indexOfScalar(u8, key, '.') != null or std.mem.eql(u8, key, "[computed]")) return self.warning(false, "computed callable key cannot be represented by the supported property path; use an explicit adapter");
            const combined = if (path) |suffix| try std.fmt.allocPrint(self.allocator, "{s}.{s}", .{ key, suffix }) else try self.allocator.dupe(u8, key);
            defer self.allocator.free(combined);
            return self.inspectShape(node, shape.values[0], combined, immutable, depth + 1);
        }
        if (std.mem.eql(u8, shape.kind, "projection") or std.mem.eql(u8, shape.kind, "declaration_projection") or std.mem.eql(u8, shape.kind, "declaration_iteration")) {
            if (shape.values.len == 0) return self.unknownProjection(path);
            const combined = if (shape.path) |prefix| if (path) |suffix| try std.fmt.allocPrint(self.allocator, "{s}.{s}", .{ prefix, suffix }) else try self.allocator.dupe(u8, prefix) else if (path) |suffix| try self.allocator.dupe(u8, suffix) else null;
            defer if (combined) |value| self.allocator.free(value);
            return self.inspectShape(node, shape.values[0], combined, immutable, depth + 1);
        }

        if (std.mem.eql(u8, shape.kind, "reference")) {
            const name = shape.name orelse return self.unknownProjection(path);
            const combined = if (shape.path) |prefix| if (path) |suffix| try std.fmt.allocPrint(self.allocator, "{s}.{s}", .{ prefix, suffix }) else try self.allocator.dupe(u8, prefix) else if (path) |suffix| try self.allocator.dupe(u8, suffix) else null;
            defer if (combined) |value| self.allocator.free(value);
            return self.inspectReference(node, name, combined, immutable, depth + 1);
        }
        if (std.mem.eql(u8, shape.kind, "call")) {
            if (shape.factory) |name| {
                if (std.mem.startsWith(u8, name, "global:Object.")) {
                    if (shape.values.len > 0) return self.inspectShape(node, shape.values[0], path, immutable, depth + 1);
                } else if (try self.factory(node, name, 0)) |contract| {
                    const previous_contract = self.inspecting_contract;
                    self.inspecting_contract = true;
                    defer self.inspecting_contract = previous_contract;
                    if (shape.values.len > 0) {
                        const frozen = immutable or std.mem.eql(u8, contract, "snapshot");
                        if (!frozen) try self.ownShape(node, shape.values[0], depth + 1);
                        return self.inspectShape(node, shape.values[0], path, frozen, depth + 1);
                    }
                }
            }
            if (shape.factory) |factory_name| if (try self.inspectCallReturn(node, factory_name, path, immutable, depth + 1, .{ .node = node, .values = shape.values, .expanded = shape.arguments_expanded })) return;
            if (self.coercing != 0 and (shape.callee != null or shape.callee_value != null)) return self.convertedResult(node, shape, self.coercing, depth + 1, false);
            return self.unknownProjection(path);
        }
        if (path == null and self.coercing & 8 != 0 and !self.invoking) return self.inspectJson(node, shape, self.json_key, immutable, depth + 1, self.json_skip_hook);
        if (std.mem.eql(u8, shape.kind, "class")) {
            if (path != null or self.invoking) try self.warning(false, "class state and callable properties are outside the plain-data tracking contract");
            return;
        }
        if (std.mem.eql(u8, shape.kind, "function")) {
            if (self.converting_call) |arguments| {
                if (self.callable_resolved) |resolved| resolved.* = true;
                for (self.callable_trail.items) |active| if (active.node == node and active.scope_id == shape.scope_id) return self.warning(false, "contextual callback invocation has an unresolved recursive cycle; expose observable data or use an adapter");
                if (self.callable_visits >= 128 or self.callable_trail.items.len >= 16) return self.warning(false, "contextual callback analysis reached the invocation limit; expose observable data or use an adapter");
                self.callable_visits += 1;
                try self.callable_trail.append(self.allocator, .{ .node = node, .scope_id = shape.scope_id });
                defer _ = self.callable_trail.pop();
                self.converting_call = null;
                defer self.converting_call = arguments;
                if (shape.async_result or shape.generator_result) return self.warning(false, "callable returns a Promise or iterator outside the plain-data tracking contract");
                const shallow = self.shallow_invocation;
                const receiver = self.receiver;
                self.shallow_invocation = true;
                if (shape.lexical_this) self.receiver = null;
                defer self.shallow_invocation = shallow;
                defer self.receiver = receiver;
                const parameters = ParameterScope{ .caller = arguments.node, .values = arguments.values, .expanded = arguments.expanded, .parent = self.parameters, .owner = shape.scope_id, .owner_node = node, .argument_scope = arguments.scope, .scoped_arguments = arguments.scoped, .receiver = if (shape.lexical_this) null else self.receiver };
                const previous_parameters = self.parameters;
                if (self.spread_result) |expansion| {
                    if (expansion.frames.items.len >= 128) return self.warning(false, "callback spread result exceeds the invocation-frame limit");
                    self.parameters = try expansion.addFrame(self.allocator, parameters);
                } else self.parameters = &parameters;
                defer self.parameters = previous_parameters;
                try self.inspectShape(node, shape, null, immutable, depth + 1);
                const invoking = self.invoking;
                self.invoking = false;
                defer self.invoking = invoking;
                if (self.spread_result) |expansion| {
                    if (shape.returns.len != 1) return self.warning(false, "callback spread result has an unverified argument layout; return a known array or use an adapter");
                    const expanded = try self.expandNativeSpread(node, shape.returns[0], expansion, depth + 1);
                    if (self.spread_proven) |proven| proven.* = expanded;
                    if (!expanded) try self.warning(false, "callback spread result has an unverified argument layout; return a known array or use an adapter");
                    return;
                }
                if (shape.returns.len == 0) return self.warning(false, "callable result provenance is unverified");
                for (shape.returns) |returned| try self.inspectShape(node, returned, null, immutable, depth + 1);
                return;
            }
            if (self.coercing != 0 and !self.invoking and path == null) try self.warning(false, "callable conversion properties are outside the plain-data tracking contract");
            if (path != null) return self.warning(false, "wrapping does not track or freeze callable properties; project plain data instead");
            if (!self.invoking) return;
            const previous_ownership = self.owning_only;
            self.owning_only = false;
            defer self.owning_only = previous_ownership;
            const active = if (self.shallow_invocation and shape.invocation != null) shape.invocation.?.* else shape;
            for (shape.captured_opaque_paths) |capture_path| {
                var proven = active.captured_shapes.len > 0;
                if (std.mem.indexOfScalar(u8, capture_path, '.')) |dot| {
                    for (active.captured_shapes) |capture| if (!try self.ownDataPath(node, capture, capture_path[dot + 1 ..], 0)) {
                        proven = false;
                    };
                } else proven = false;
                if (proven) continue;
                try self.labels.append(self.allocator, capture_path);
                defer _ = self.labels.pop();
                try self.warning(false, "captured path may address untracked callable properties or computed members; project supported plain data or use a subscription adapter");
            }
            var unverified_capture = active.captured_locals.len > 0;
            for (active.captured_shapes) |capture| if (!try self.passiveCapture(node, capture, 0) and !try self.captureSubscription(node, capture, 0)) {
                unverified_capture = true;
            };
            if (unverified_capture) try self.warning(false, "returned callable captures helper-local values without a verified subscription path; expose observable data or a subscription adapter");
            if (!node.component) self.indirect += 1;
            defer if (!node.component) {
                self.indirect -= 1;
            };
            try self.projectedResults(node, active.result_projections);
            try self.retainedCalls(node, active.retained_local_calls);
            if (active.retained_local_state) try self.warning(false, "callable closures retain raw local state outside declaration lowering; create observable state inside the helper");
            if (active.has_mutation) try self.warning(false, "wrapped callable contains mutations; render effects are unverified");
            if (self.shallow_invocation) if (shape.invocation) |effects| {
                try self.traceInvocation(node, effects.*);
                return;
            };
            try self.inspectEffects(node, shape.effects, false);
            for (shape.accesses) |access| {
                const previous_coercion = self.coercing;
                self.coercing = coerces(node, shape.coercions, access);
                defer self.coercing = previous_coercion;
                const previous = self.invoking;
                self.invoking = access.call;
                defer self.invoking = previous;
                if (hasLocal(node, access.name)) try self.trace(node, access.name, access.path, false) else if (!knownGlobal(access.name)) try self.globalWarning(access.name, access.path);
            }
            for (shape.globals) |global| {
                const receiver_owner = if (shape.invocation) |effects| effects.scope_id else null;
                if (!knownGlobal(global) and !hasLocal(node, global) and !(std.mem.eql(u8, global, "this") and self.hasOwnedReceiver(node, receiver_owner))) try self.globalWarning(global, null);
            }
            for (shape.calls) |call| {
                const dot = std.mem.indexOfScalar(u8, call, '.');
                const root = if (dot) |index| call[0..index] else call;
                if (!hasLocal(node, root) and (!knownGlobal(root) or (dot != null and !knownIntrinsicCall(call)))) try self.warning(false, "wrapped callable invokes an opaque callback or method");
            }
            return;
        }
        if (path == null and self.coercing != 0 and !self.invoking) {
            if (std.mem.eql(u8, shape.kind, "record")) {
                for (shape.properties) |property| {
                    if (property.name == null) try self.warning(false, "computed object keys may define an unverified conversion hook") else if (std.mem.eql(u8, property.name.?, "__proto__")) try self.warning(false, "custom prototype conversion hooks have unverified coverage; expose observable plain data");
                }
                if (self.coercing & 4 != 0) {
                    var locale: ?ValueShape = null;
                    var index = shape.properties.len;
                    while (index > 0) {
                        index -= 1;
                        const property = shape.properties[index];
                        if (property.name != null and std.mem.eql(u8, property.name.?, "toLocaleString")) {
                            locale = property.value;
                            break;
                        }
                    }
                    if (locale) |value| {
                        const previous = self.invoking;
                        self.invoking = true;
                        defer self.invoking = previous;
                        try self.labels.append(self.allocator, "implicit toLocaleString()");
                        defer _ = self.labels.pop();
                        try self.inspectShape(node, value, null, immutable, depth + 1);
                    } else try self.inspectConversion(node, shape, immutable, depth + 1, false);
                }
                if (self.coercing & 1 != 0) try self.inspectConversion(node, shape, immutable, depth + 1, false);
                if (self.coercing & 2 != 0) try self.inspectConversion(node, shape, immutable, depth + 1, true);
            } else if (std.mem.eql(u8, shape.kind, "array")) {
                for (shape.values) |value| try self.inspectShape(node, value, null, immutable, depth + 1);
            }
        }
        if (path) |member_path| {
            const dot = std.mem.indexOfScalar(u8, member_path, '.') orelse member_path.len;
            const member = member_path[0..dot];
            const rest = if (dot < member_path.len) member_path[dot + 1 ..] else null;
            if (std.mem.eql(u8, shape.kind, "record")) {
                if (std.mem.eql(u8, member, "[computed]")) {
                    for (shape.properties) |property| try self.inspectShape(node, property.value, rest, immutable, depth + 1);
                    return;
                }
                var index = shape.properties.len;
                while (index > 0) {
                    index -= 1;
                    const property = shape.properties[index];
                    const key = property.name orelse return self.unknownProjection(member_path);
                    if (std.mem.eql(u8, key, member)) return self.inspectShape(node, property.value, rest, immutable, depth + 1);
                }
                if (contains(&.{ "toString", "toLocaleString", "valueOf", "hasOwnProperty", "propertyIsEnumerable", "isPrototypeOf" }, member)) {
                    if (rest != null) return self.warning(false, "callable properties are outside the plain-data tracking contract");
                    return;
                }
                if (rest == null and !self.invoking) return;
                return self.unknownProjection(rest);
            }
            if (std.mem.eql(u8, shape.kind, "array")) {
                if (std.mem.eql(u8, member, "[computed]")) {
                    for (shape.values) |value| try self.inspectShape(node, value, rest, immutable, depth + 1);
                    return;
                }
                if (std.mem.eql(u8, member, "length") and rest == null and !self.invoking) return;
                if (contains(&.{ "map", "filter", "reduce", "reduceRight", "find", "findIndex", "findLast", "findLastIndex", "some", "every", "includes", "indexOf", "lastIndexOf", "at", "flat", "flatMap", "slice", "join", "concat", "toString", "toLocaleString", "entries", "keys", "values", "toReversed", "toSorted", "toSpliced", "with" }, member)) {
                    if (rest != null) return self.warning(false, "callable properties on native array methods are outside the plain-data tracking contract");
                    if (self.invoking and contains(&.{ "join", "toString", "toLocaleString" }, member)) {
                        const previous_invoking = self.invoking;
                        const previous_coercion = self.coercing;
                        self.invoking = false;
                        self.coercing = if (std.mem.eql(u8, member, "toLocaleString")) 4 else 1;
                        defer self.invoking = previous_invoking;
                        defer self.coercing = previous_coercion;
                        for (shape.values) |value| try self.inspectShape(node, value, null, immutable, depth + 1);
                    }
                    return;
                }
                if (immutable and contains(&.{ "push", "pop", "shift", "unshift", "splice", "sort", "reverse", "fill", "copyWithin" }, member)) return self.warning(false, "render calls a mutating method on snapshot data");
                if (std.fmt.parseInt(usize, member, 10)) |index| {
                    if (index < shape.values.len) return self.inspectShape(node, shape.values[index], rest, immutable, depth + 1);
                } else |_| {}
                return self.unknownProjection(rest);
            }
            return self.unknownProjection(member_path);
        }
        if (self.invoking) try self.warning(false, "wrapped value has no verified callable implementation or subscription path");
    }

    // Plain-data aliases inside the compilation boundary must be replaced at
    // their declarations too. Registering only their receiving object would
    // leave writes through the original managed alias raw.
    fn declarationSourceContract(self: *Context, node: *Node, shape: ValueShape, depth: usize) anyerror!bool {
        if (depth >= 32) return false;
        if (std.mem.eql(u8, shape.kind, "call") and shape.factory != null) {
            const name = shape.factory.?;
            if (try self.factory(node, name, 0) != null) return true;
            const resolved = blk: {
                const dot = std.mem.indexOfScalar(u8, name, '.') orelse break :blk try self.namespaceRoot(node, name, 0);
                var origin = try self.namespaceRoot(node, name[0..dot], 0);
                var parts = std.mem.splitScalar(u8, name[dot + 1 ..], '.');
                while (parts.next()) |part| {
                    if (origin != .found or origin.found.node == null or !std.mem.eql(u8, origin.found.name, "*namespace*")) break :blk .unknown;
                    var seen = std.ArrayList(Trail).empty;
                    defer seen.deinit(self.allocator);
                    origin = try self.resolveExport(origin.found.node.?, part, &seen);
                }
                break :blk origin;
            };
            if (resolved != .found or resolved.found.node == null) return false;
            const target = resolved.found.node.?;
            for (target.parsed.value.bindings) |binding| {
                if (!std.mem.eql(u8, binding.name, resolved.found.name)) continue;
                if (contains(target.parsed.value.root_writes, binding.name) or binding.shape.async_result or binding.shape.generator_result or binding.shape.returns.len == 0) return false;
                for (binding.shape.returns) |returned| {
                    if ((target.component or self.owns(target)) and try self.plainTrackedShape(target, returned, depth + 1)) continue;
                    if (!try self.declarationSourceContract(target, returned, depth + 1)) return false;
                }
                return true;
            }
            return false;
        }
        if (std.mem.eql(u8, shape.kind, "reference") and shape.name != null and shape.path == null) {
            for (node.parsed.value.imports) |record| {
                if (!std.mem.eql(u8, record.local, shape.name.?)) continue;
                var seen = std.ArrayList(Trail).empty;
                defer seen.deinit(self.allocator);
                const resolved = try self.resolveImportOrigin(node, record.source, record.imported, &seen);
                if (resolved == .found and resolved.found.node != null) return self.declarationSourceContract(resolved.found.node.?, .{ .kind = "reference", .name = resolved.found.name }, depth + 1);
                return false;
            }
            for (node.parsed.value.bindings) |binding| {
                if (std.mem.eql(u8, binding.name, shape.name.?) and !contains(node.parsed.value.root_writes, binding.name)) return self.declarationSourceContract(node, binding.shape, depth + 1);
            }
        }
        return false;
    }

    fn ownShape(self: *Context, node: *Node, shape: ValueShape, depth: usize) anyerror!void {
        if (depth >= 64) return;
        if (contains(&.{ "declaration_projection", "destructure_rest", "declaration_iteration", "declaration_array_rest" }, shape.kind)) {
            for (shape.values) |source| {
                if (std.mem.eql(u8, shape.kind, "declaration_iteration") or std.mem.eql(u8, shape.kind, "declaration_array_rest")) {
                    var expansion = NativeArguments{};
                    defer expansion.deinit(self.allocator);
                    const previous = self.declaration_iterator;
                    self.declaration_iterator = true;
                    defer self.declaration_iterator = previous;
                    if (!try self.expandNativeSpread(node, source, &expansion, 0)) try self.warning(false, "array destructuring source has an unverified iterator; expose observable data or use an adapter");
                }
                if (try self.plainTrackedShape(node, source, 0) or try self.declarationSourceContract(node, source, 0)) {
                    try self.ownShape(node, source, depth + 1);
                } else try self.warning(false, "destructuring source has unverified alias ownership; expose observable data or use an adapter");
            }
            return;
        }
        if (std.mem.eql(u8, shape.kind, "parameter")) {
            if (try self.possibleDefault(node, shape)) try self.ownShape(node, shape.values[0], depth + 1);
            const value = self.parameterValue(node, shape) orelse return;
            const previous = self.parameters;
            self.parameters = value.scope;
            defer self.parameters = previous;
            return self.ownShape(value.node, value.shape, depth + 1);
        }
        if (contains(&.{ "logical", "conditional", "sequence" }, shape.kind)) {
            if (try self.branchChoice(node, shape, depth + 1)) |index| return self.ownShape(node, shape.values[index], depth + 1);
            const start: usize = if (std.mem.eql(u8, shape.kind, "conditional")) 1 else 0;
            for (shape.values[start..]) |value| try self.ownShape(node, value, depth + 1);
            return;
        }
        if (std.mem.eql(u8, shape.kind, "reference")) {
            const name = shape.name orelse return;
            for (node.parsed.value.imports) |record| {
                if (!std.mem.eql(u8, record.local, name)) continue;
                var seen = std.ArrayList(Trail).empty;
                defer seen.deinit(self.allocator);
                const resolved = try self.resolveImportOrigin(node, record.source, record.imported, &seen);
                if (resolved == .found and resolved.found.node != null and !std.mem.eql(u8, resolved.found.name, "*namespace*")) {
                    var reference = ValueShape{ .kind = "reference", .name = resolved.found.name };
                    reference.path = shape.path;
                    try self.ownShape(resolved.found.node.?, reference, depth + 1);
                }
                return;
            }
            if (!node.component and !self.owns(node)) return;
            for (node.parsed.value.bindings) |binding| {
                if (!std.mem.eql(u8, binding.name, name)) continue;
                if (std.mem.eql(u8, binding.value_kind, "function") or std.mem.eql(u8, binding.value_kind, "class")) return;
                if (std.mem.eql(u8, binding.value_kind, "unknown") and binding.shape.kind.len == 0) return;
                if (!std.mem.eql(u8, binding.declaration_kind, "let") and !std.mem.eql(u8, binding.declaration_kind, "const")) return;
                if (self.plan) |plan| {
                    if (node.component) try plan.selectLocal(self.allocator, self.model.source_path, name) else try plan.normalize(self.allocator, node.path, name, self.model.source_path);
                }
                return self.ownShape(node, binding.shape, depth + 1);
            }
            return;
        }
        if (std.mem.eql(u8, shape.kind, "function") or std.mem.eql(u8, shape.kind, "class")) return;
        if (std.mem.eql(u8, shape.kind, "call")) {
            if (shape.factory) |name| if (try self.factory(node, name, 0)) |contract| {
                if (std.mem.eql(u8, contract, "snapshot")) return;
            };
        }
        for (shape.properties) |property| try self.ownShape(node, property.value, depth + 1);
        for (shape.values) |value| try self.ownShape(node, value, depth + 1);
    }

    fn unknownProjection(self: *Context, path: ?[]const u8) !void {
        if (self.invoking) return self.warning(false, if (path != null) "wrapped callable property provenance is unknown; wrapping does not make its effects reactive" else "wrapped callable provenance is unknown; wrapping does not make its effects reactive");
        if (self.inspecting_return and !self.inspecting_contract) return self.warning(false, "helper return-value provenance is unresolved; expose observable plain data");
        // Explicit contracts cover passive data. Unknown data layout alone is
        // not evidence of a callable effect or an unsupported function property.
    }

    fn inspectReference(self: *Context, node: *Node, name: []const u8, path: ?[]const u8, immutable: bool, depth: usize) anyerror!void {
        if (depth >= 64) return self.unknownProjection(path);
        if (path == null and self.converting_call != null and self.expression_entry == node) if (self.covered_callbacks) |covered| try covered.put(name, {});
        const label = try std.fmt.allocPrint(self.allocator, "{s}::{s}{s}{s}", .{ node.path, name, if (path != null) "." else "", path orelse "" });
        defer self.allocator.free(label);
        try self.labels.append(self.allocator, label);
        defer _ = self.labels.pop();
        for (node.parsed.value.imports) |record| {
            if (!std.mem.eql(u8, record.local, name)) continue;
            const previous_indirect = self.indirect;
            if (node.component and !std.mem.eql(u8, record.imported, "*")) {
                self.indirect = 0;
                if (!self.owning_only) if (self.plan) |plan| try plan.watchImported(self.allocator, self.model.source_path, name, self.render_binding, false);
            }
            defer self.indirect = previous_indirect;
            var seen = std.ArrayList(Trail).empty;
            defer seen.deinit(self.allocator);
            const resolved = try self.resolveImportOrigin(node, record.source, record.imported, &seen);
            if (resolved != .found) {
                if (!self.inspecting_contract) return self.traceImport(node, record.source, record.imported, path);
                const imported_label = try std.fmt.allocPrint(self.allocator, "{s}::{s}", .{ record.source, record.imported });
                defer self.allocator.free(imported_label);
                try self.labels.append(self.allocator, imported_label);
                defer _ = self.labels.pop();
                return self.unknownProjection(path);
            }
            return self.inspectOrigin(resolved.found, path, immutable, depth + 1);
        }
        for (node.parsed.value.bindings) |binding| {
            if (!std.mem.eql(u8, binding.name, name)) continue;
            if (self.converting_call != null and path == null and std.mem.eql(u8, binding.shape.kind, "function")) {
                if (contains(node.parsed.value.root_writes, name)) return self.warning(false, "reassigned callback has unverified implementation and subscription effects; expose a stable callable or use an adapter");
                return self.inspectShape(node, binding.shape, null, immutable, depth + 1);
            }
            if (std.mem.eql(u8, binding.value_kind, "function") and self.coercing & 8 != 0 and !self.invoking and path == null) return self.trace(node, name, null, false);
            if (std.mem.eql(u8, binding.value_kind, "function") or std.mem.eql(u8, binding.value_kind, "class")) {
                if (path != null) return self.warning(false, "wrapping does not track or freeze callable properties; project plain data instead");
                if (self.invoking) {
                    if (binding.has_mutation) try self.warning(false, "wrapped callable contains mutations; render effects are unverified");
                    return self.trace(node, name, null, false);
                }
                return;
            }
            if (!immutable and !self.inspecting_contract and !node.component and !self.owns(node)) return self.trace(node, name, path, false);
            return self.inspectShape(node, binding.shape, path, immutable, depth + 1);
        }
        if (knownGlobal(name)) return;
        if (!self.inspecting_contract) return self.globalWarning(name, path);
        return self.unknownProjection(path);
    }

    fn inspectOrigin(self: *Context, origin: Origin, path: ?[]const u8, immutable: bool, depth: usize) anyerror!void {
        const node = origin.node orelse return self.unknownProjection(path);
        if (std.mem.eql(u8, origin.name, "*namespace*")) {
            const member_path = path orelse return self.unknownProjection(path);
            const dot = std.mem.indexOfScalar(u8, member_path, '.') orelse member_path.len;
            var seen = std.ArrayList(Trail).empty;
            defer seen.deinit(self.allocator);
            const resolved = try self.resolveExport(node, member_path[0..dot], &seen);
            if (resolved != .found) return self.unknownProjection(path);
            return self.inspectOrigin(resolved.found, if (dot < member_path.len) member_path[dot + 1 ..] else null, immutable, depth + 1);
        }
        return self.inspectReference(node, origin.name, path, immutable, depth + 1);
    }

    fn inspectIncoming(self: *Context, node: *Node, assignment: Assignment, path: ?[]const u8, immutable: bool) anyerror!void {
        var relative = path;
        if (assignment.path) |destination| {
            const requested = path orelse return;
            if (std.mem.eql(u8, requested, destination)) {
                relative = null;
            } else if (requested.len > destination.len and std.mem.startsWith(u8, requested, destination) and requested[destination.len] == '.') {
                relative = requested[destination.len + 1 ..];
            } else return;
        }
        if (contains(&.{ "push", "unshift", "splice", "fill" }, assignment.operator)) {
            const requested = relative orelse return;
            if (std.mem.eql(u8, requested, "[computed]")) relative = null else if (std.mem.startsWith(u8, requested, "[computed].")) relative = requested["[computed].".len..] else return;
        }
        if (assignment.projected) return self.unknownProjection(relative);
        return self.inspectShape(node, assignment.value.shape, relative, immutable, 0);
    }

    fn verifiedArgumentConsumer(self: *Context, node: *Node, callee: []const u8, depth: usize) anyerror!bool {
        if (depth >= 32) return false;
        if (std.mem.startsWith(u8, callee, "global:")) {
            const native = callee[7..];
            return knownIntrinsicCall(native) or contains(&.{ "String", "Number", "Boolean", "BigInt", "Symbol", "parseInt", "parseFloat", "isFinite", "isNaN" }, native);
        }
        if (try self.factory(node, callee, 0)) |_| return true;
        // These insertion calls already have explicit incoming-value facts.
        if (std.mem.lastIndexOfScalar(u8, callee, '.')) |dot| {
            if (contains(&.{ "push", "unshift", "splice", "fill" }, callee[dot + 1 ..]) and try self.arrayBinding(node, callee[0..dot], callee[dot + 1 ..], 0)) return true;
            return false;
        }
        for (node.parsed.value.bindings) |binding| {
            if (!std.mem.eql(u8, binding.name, callee)) continue;
            if (!std.mem.eql(u8, binding.value_kind, "function") or binding.has_mutation or binding.retained_local_state or contains(node.parsed.value.root_writes, callee)) return false;
            for (binding.retained_local_calls) |factory_name| if (try self.factory(node, factory_name, 0) == null) return false;
            for (binding.calls) |call| {
                // Function facts retain native names without the global prefix.
                if (std.mem.indexOfScalar(u8, call, '.')) |dot| {
                    if (!hasLocal(node, call[0..dot]) and knownIntrinsicCall(call)) continue;
                } else if (!hasLocal(node, call) and knownGlobal(call)) continue;
                if (!try self.verifiedArgumentConsumer(node, call, depth + 1)) return false;
            }
            return true;
        }
        return false;
    }

    // Follow containers/aliases in the reverse direction when a selected value
    // is passed to a consumer inside an argument tuple or destination holder.
    fn containsReference(self: *Context, node: *Node, shape: ValueShape, name: []const u8, depth: usize) anyerror!bool {
        if (depth >= 32) return false;
        if (std.mem.eql(u8, shape.kind, "reference")) {
            const reference = shape.name orelse return false;
            if (std.mem.eql(u8, reference, name)) return true;
            for (node.parsed.value.bindings) |binding| {
                if (std.mem.eql(u8, binding.name, reference)) return self.containsReference(node, binding.shape, name, depth + 1);
            }
            return false;
        }
        if (!std.mem.eql(u8, shape.kind, "record") and !std.mem.eql(u8, shape.kind, "array")) return false;
        for (shape.values) |value| if (try self.containsReference(node, value, name, depth + 1)) return true;
        for (shape.properties) |property| if (try self.containsReference(node, property.value, name, depth + 1)) return true;
        return false;
    }

    fn argumentContains(self: *Context, node: *Node, target: []const u8, name: []const u8) anyerror!bool {
        if (std.mem.eql(u8, target, name)) return true;
        for (node.parsed.value.bindings) |binding| {
            if (std.mem.eql(u8, binding.name, target)) return self.containsReference(node, binding.shape, name, 0);
        }
        return false;
    }

    fn traceIncoming(self: *Context, node: *Node, name: []const u8, path: ?[]const u8) anyerror!void {
        return self.traceIncomingWithFlows(node, name, path, true);
    }

    fn traceIncomingWithFlows(self: *Context, node: *Node, name: []const u8, path: ?[]const u8, flows: bool) anyerror!void {
        var explicit_contract = false;
        for (node.parsed.value.bindings) |binding| {
            if (!std.mem.eql(u8, binding.name, name) or contains(node.parsed.value.root_writes, name)) continue;
            explicit_contract = std.mem.eql(u8, binding.value_kind, "observable") or std.mem.eql(u8, binding.value_kind, "snapshot");
            if (binding.factory) |factory_name| if (try self.factory(node, factory_name, 0)) |_| {
                explicit_contract = true;
            };
        }
        for (node.parsed.value.argument_flows) |flow| {
            if (!flows) continue;
            if (explicit_contract) continue;
            if (!try self.argumentContains(node, flow.target, name)) continue;
            // These native destination calls are covered by detailed incoming
            // assignments only for direct, unexpanded argument identities.
            const modeled = contains(&.{ "global:Object.assign", "global:Object.defineProperty", "global:Object.defineProperties", "global:Reflect.defineProperty", "global:Reflect.set" }, flow.callee);
            const destination = flow.argument_index == 0 or (std.mem.eql(u8, flow.callee, "global:Reflect.set") and flow.argument_index == 3);
            if (modeled and !flow.spread and (!destination or (!flow.indirect and std.mem.eql(u8, flow.target, name)))) continue;
            if (!flow.spread and try self.verifiedArgumentConsumer(node, flow.callee, 0)) continue;
            const label = try std.fmt.allocPrint(self.allocator, "argument to {s}", .{flow.callee});
            defer self.allocator.free(label);
            try self.labels.append(self.allocator, label);
            defer _ = self.labels.pop();
            try self.warning(false, "state is passed to a helper whose incoming mutations and retained aliases are unverified; use an explicit observable integration contract");
        }
        for (node.parsed.value.assignments) |assignment| {
            if (!std.mem.eql(u8, assignment.target, name)) continue;
            const value = assignment.value;
            const previous_ownership = self.owning_only;
            self.owning_only = !std.mem.eql(u8, value.value_kind, "function");
            defer self.owning_only = previous_ownership;
            // Explicit contracts validate the whole incoming graph at runtime.
            if (std.mem.eql(u8, value.value_kind, "observable") or std.mem.eql(u8, value.value_kind, "snapshot")) {
                try self.inspectIncoming(node, assignment, path, std.mem.eql(u8, value.value_kind, "snapshot"));
                continue;
            }
            if (std.mem.eql(u8, value.value_kind, "call")) if (value.factory) |factory_name| {
                if (try self.factory(node, factory_name, 0)) |contract| {
                    try self.inspectIncoming(node, assignment, path, std.mem.eql(u8, contract, "snapshot"));
                    continue;
                }
            };
            const named = assignment.operator.len > 0 and std.ascii.isAlphabetic(assignment.operator[0]);
            const label = try std.fmt.allocPrint(self.allocator, "incoming{s}{s}{s}{s}{s}", .{ if (named) "(" else "", if (named) assignment.operator else "", if (named) ")" else "", if (assignment.path != null) "." else "", assignment.path orelse "" });
            defer self.allocator.free(label);
            try self.labels.append(self.allocator, label);
            defer _ = self.labels.pop();
            // A proven primitive is captured by value. Neither its input object
            // nor a native receiver becomes part of the receiving reactive graph.
            if (std.mem.eql(u8, value.value_kind, "primitive") or contains(&.{ "primitive", "undefined" }, value.shape.kind)) continue;
            if (assignment.inputs.len > 0 or std.mem.eql(u8, value.value_kind, "input")) {
                try self.warning(false, "assigned value comes from a local or parameter whose ownership is unverified");
            }
            for (value.accesses) |access| {
                if (std.mem.eql(u8, access.name, name)) continue;
                if (hasLocal(node, access.name)) {
                    try self.trace(node, access.name, access.path, false);
                } else if (!knownGlobal(access.name)) {
                    try self.globalWarning(access.name, access.path);
                }
            }
            for (value.globals) |global| {
                if (knownGlobal(global)) continue;
                var covered = false;
                for (value.accesses) |access| if (std.mem.eql(u8, access.name, global)) {
                    covered = true;
                };
                if (!covered) try self.globalWarning(global, null);
            }
            if (std.mem.eql(u8, value.value_kind, "call") and value.factory == null) {
                var has_opaque_call = value.calls.len == 0;
                for (value.calls) |call| {
                    if (!knownIntrinsicCall(call) and !knownGlobal(call)) has_opaque_call = true;
                }
                if (has_opaque_call) try self.warning(false, "assignment invokes an opaque function");
            }
        }
    }

    fn traceImport(self: *Context, node: *Node, source: []const u8, imported_name: []const u8, path: ?[]const u8) anyerror!void {
        const previous_indirect = self.indirect;
        if (node.component and !std.mem.eql(u8, imported_name, "*")) self.indirect = 0;
        defer self.indirect = previous_indirect;
        if (std.mem.eql(u8, source, "weiv:observable")) {
            var candidate = imported_name;
            var property = path;
            if (std.mem.eql(u8, imported_name, "*")) {
                const access = path orelse return;
                const dot = std.mem.indexOfScalar(u8, access, '.') orelse access.len;
                candidate = access[0..dot];
                property = if (dot < access.len) access[dot + 1 ..] else null;
            }
            if (contains(&.{ "observable", "snapshot", "subscribe", "isObservable", "observableBrandSymbol" }, candidate)) {
                if (property != null) return self.warning(false, "function properties are outside the observable data contract");
                return;
            }
            return self.warning(false, "unrecognized observable runtime export");
        }
        if (try self.imported(node, source)) |target| {
            if (std.mem.eql(u8, imported_name, "*")) {
                if (path) |member_path| {
                    const dot = std.mem.indexOfScalar(u8, member_path, '.') orelse member_path.len;
                    self.indirect += 1;
                    defer self.indirect -= 1;
                    return self.trace(target, member_path[0..dot], if (dot < member_path.len) member_path[dot + 1 ..] else null, true);
                }
                try self.warning(false, "whole or dynamically accessed module namespace");
                return;
            }
            return self.trace(target, imported_name, path, true);
        }
        const label = try std.fmt.allocPrint(self.allocator, "{s}::{s}", .{ source, imported_name });
        defer self.allocator.free(label);
        try self.labels.append(self.allocator, label);
        defer _ = self.labels.pop();
        try self.warning(false, "external module implementation or notification contract is unavailable");
    }

    fn factory(self: *Context, node: *Node, name: []const u8, depth: usize) anyerror!?[]const u8 {
        const dot = std.mem.indexOfScalar(u8, name, '.');
        return self.factoryLocal(node, if (dot) |d| name[0..d] else name, if (dot) |d| name[d + 1 ..] else null, depth);
    }

    fn factoryLocal(self: *Context, node: *Node, name: []const u8, member: ?[]const u8, depth: usize) anyerror!?[]const u8 {
        if (depth >= 64 or contains(node.parsed.value.root_writes, name)) return null;
        for (node.parsed.value.imports) |record| {
            if (!std.mem.eql(u8, record.local, name)) continue;
            return self.factoryImport(node, record.source, record.imported, member, depth + 1);
        }
        for (node.parsed.value.bindings) |binding| {
            if (!std.mem.eql(u8, binding.name, name)) continue;
            if (binding.alias) |alias| return self.factoryLocal(node, alias, member, depth + 1);
        }
        return null;
    }

    fn factoryImport(self: *Context, node: *Node, source: []const u8, name: []const u8, member: ?[]const u8, depth: usize) anyerror!?[]const u8 {
        if (depth >= 64) return null;
        if (std.mem.eql(u8, source, "weiv:observable")) {
            const candidate = if (std.mem.eql(u8, name, "*")) member orelse return null else if (member == null) name else return null;
            if (std.mem.eql(u8, candidate, "observable")) return "observable";
            if (std.mem.eql(u8, candidate, "snapshot")) return "snapshot";
            return null;
        }
        const target = (try self.imported(node, source)) orelse return null;
        if (std.mem.eql(u8, name, "*")) return self.factoryExport(target, member orelse return null, null, depth + 1);
        return self.factoryExport(target, name, member, depth + 1);
    }

    fn factoryExport(self: *Context, node: *Node, name: []const u8, member: ?[]const u8, depth: usize) anyerror!?[]const u8 {
        if (depth >= 64) return null;
        var seen = std.ArrayList(Trail).empty;
        defer seen.deinit(self.allocator);
        const resolved = try self.resolveExport(node, name, &seen);
        if (resolved != .found) return null;
        const origin = resolved.found;
        if (origin.external) |source| {
            if (!std.mem.eql(u8, source, "weiv:observable")) return null;
            const candidate = if (std.mem.eql(u8, origin.name, "*namespace*")) member orelse return null else if (member == null) origin.name else return null;
            if (std.mem.eql(u8, candidate, "observable")) return "observable";
            if (std.mem.eql(u8, candidate, "snapshot")) return "snapshot";
            return null;
        }
        const target = origin.node orelse return null;
        if (std.mem.eql(u8, origin.name, "*namespace*")) return self.factoryExport(target, member orelse return null, null, depth + 1);
        return self.factoryLocal(target, origin.name, member, depth + 1);
    }

    fn traceExport(self: *Context, node: *Node, name: []const u8, path: ?[]const u8) anyerror!void {
        for (node.parsed.value.exports) |export_record| {
            if (!std.mem.eql(u8, export_record.exported, name) or std.mem.eql(u8, export_record.kind, "star")) continue;
            if (export_record.local) |local| return self.trace(node, local, path, false);
            if (export_record.source) |source| return self.traceImport(node, source, export_record.imported orelse "*", path);
        }
        var seen = std.ArrayList(Trail).empty;
        defer seen.deinit(self.allocator);
        const resolved = try self.resolveExport(node, name, &seen);
        switch (resolved) {
            .found => |origin| {
                if (origin.external) |source| return self.traceImport(node, source, if (std.mem.eql(u8, origin.name, "*namespace*")) "*" else origin.name, path);
                const target = origin.node orelse unreachable;
                if (std.mem.eql(u8, origin.name, "*namespace*")) {
                    if (path) |member_path| {
                        const dot = std.mem.indexOfScalar(u8, member_path, '.') orelse member_path.len;
                        self.indirect += 1;
                        defer self.indirect -= 1;
                        return self.trace(target, member_path[0..dot], if (dot < member_path.len) member_path[dot + 1 ..] else null, true);
                    }
                    return self.warning(false, "whole or dynamically accessed module namespace");
                }
                return self.trace(target, origin.name, path, false);
            },
            .ambiguous => try self.warning(false, "ambiguous star re-export"),
            .unknown => try self.warning(false, "star re-export coverage includes unavailable modules"),
            .missing => try self.warning(false, "export implementation is unavailable"),
        }
    }

    fn resolveLocalOrigin(self: *Context, node: *Node, name: []const u8, seen: *std.ArrayList(Trail)) anyerror!ExportResolution {
        for (node.parsed.value.imports) |record| {
            if (std.mem.eql(u8, record.local, name)) return self.resolveImportOrigin(node, record.source, record.imported, seen);
        }
        for (node.parsed.value.bindings) |binding| if (std.mem.eql(u8, binding.name, name)) return .{ .found = .{ .node = node, .name = name } };
        return .unknown;
    }

    fn resolveImportOrigin(self: *Context, node: *Node, source: []const u8, name: []const u8, seen: *std.ArrayList(Trail)) anyerror!ExportResolution {
        if (std.mem.eql(u8, source, "weiv:observable")) return .{ .found = .{ .external = source, .name = if (std.mem.eql(u8, name, "*")) "*namespace*" else name } };
        const target = (try self.imported(node, source)) orelse return .unknown;
        if (std.mem.eql(u8, name, "*")) return .{ .found = .{ .node = target, .name = "*namespace*" } };
        return self.resolveExport(target, name, seen);
    }

    fn resolveExport(self: *Context, node: *Node, name: []const u8, seen: *std.ArrayList(Trail)) anyerror!ExportResolution {
        if (!node.parsed.value.ok or seen.items.len >= 64) return .unknown;
        for (seen.items) |entry| if (entry.node == node and std.mem.eql(u8, entry.name, name)) return .missing;
        try seen.append(self.allocator, .{ .node = node, .name = name, .exported = true });
        defer _ = seen.pop();
        for (node.parsed.value.exports) |record| {
            if (!std.mem.eql(u8, record.exported, name) or std.mem.eql(u8, record.kind, "star")) continue;
            if (record.local) |local| return self.resolveLocalOrigin(node, local, seen);
            if (record.source) |source| return self.resolveImportOrigin(node, source, record.imported orelse "*", seen);
            return .unknown;
        }
        if (std.mem.eql(u8, name, "default")) return .missing;
        var result: ExportResolution = .missing;
        for (node.parsed.value.exports) |record| {
            if (!std.mem.eql(u8, record.kind, "star")) continue;
            const source = record.source orelse continue;
            const candidate = try self.resolveImportOrigin(node, source, name, seen);
            switch (candidate) {
                .missing => {},
                .unknown => return .unknown,
                .ambiguous => return .ambiguous,
                .found => |origin| {
                    if (result == .found) {
                        const old = result.found;
                        if (old.node != origin.node or !std.mem.eql(u8, old.name, origin.name)) return .ambiguous;
                        if (old.external != null or origin.external != null) {
                            if (old.external == null or origin.external == null or !std.mem.eql(u8, old.external.?, origin.external.?)) return .ambiguous;
                        }
                    } else result = candidate;
                },
            }
        }
        return result;
    }
};

fn hasLocal(node: *Node, name: []const u8) bool {
    for (node.parsed.value.imports) |import| if (std.mem.eql(u8, import.local, name)) return true;
    for (node.parsed.value.bindings) |binding| if (std.mem.eql(u8, binding.name, name)) return true;
    return false;
}
fn contains(names: []const []const u8, name: []const u8) bool {
    for (names) |item| if (std.mem.eql(u8, item, name)) return true;
    return false;
}
fn samePath(left: ?[]const u8, right: ?[]const u8) bool {
    if (left == null or right == null) return left == null and right == null;
    return std.mem.eql(u8, left.?, right.?);
}
fn coerces(node: *Node, accesses: []const Coercion, access: Access) u8 {
    var hints: u8 = 0;
    for (accesses) |coercion| if (std.mem.eql(u8, coercion.name, access.name) and samePath(coercion.path, access.path)) {
        if (coercion.native) |name| if (hasLocal(node, name)) continue;
        hints |= coercion.hint;
    };
    return hints;
}

fn primitiveNativeResult(name: []const u8) bool {
    return (std.mem.startsWith(u8, name, "Math.") and knownIntrinsicCall(name) and !std.mem.eql(u8, name, "Math.valueOf")) or contains(&.{ "String", "Number", "Boolean", "BigInt", "Symbol", "parseInt", "parseFloat", "isFinite", "isNaN", "JSON.stringify", "Object.keys", "Object.is", "Object.hasOwn", "Array.isArray" }, name);
}

fn knownGlobal(name: []const u8) bool {
    return contains(&.{ "undefined", "NaN", "Infinity", "Object", "Array", "Intl", "Math", "String", "Number", "Boolean", "BigInt", "Symbol", "JSON", "parseInt", "parseFloat", "isFinite", "isNaN" }, name);
}

fn knownIntrinsicCall(name: []const u8) bool {
    return contains(&.{ "Math.abs", "Math.acos", "Math.acosh", "Math.asin", "Math.asinh", "Math.atan", "Math.atanh", "Math.atan2", "Math.cbrt", "Math.ceil", "Math.clz32", "Math.cos", "Math.cosh", "Math.exp", "Math.expm1", "Math.floor", "Math.fround", "Math.f16round", "Math.hypot", "Math.imul", "Math.log", "Math.log10", "Math.log1p", "Math.log2", "Math.max", "Math.min", "Math.pow", "Math.random", "Math.round", "Math.sign", "Math.sin", "Math.sinh", "Math.sqrt", "Math.tan", "Math.tanh", "Math.trunc", "Math.toString", "Math.toLocaleString", "Math.hasOwnProperty", "Math.propertyIsEnumerable", "Math.isPrototypeOf", "Math.valueOf", "JSON.parse", "JSON.stringify" }, name) or contains(&.{ "Object.keys", "Object.values", "Object.entries", "Object.fromEntries", "Object.is", "Object.hasOwn", "Array.isArray" }, name);
}
