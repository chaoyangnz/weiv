const std = @import("std");

// Owned cross-module state selections shared by project analysis and emitters.
// This representation has no dependency on AST inference or browser codegen.
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

    pub fn watchLocal(self: *ManagedPlan, allocator: std.mem.Allocator, component_path: []const u8, name: []const u8, binding: []const u8) !void {
        try self.selectLocal(allocator, component_path, name);
        return self.watchImported(allocator, component_path, name, binding, false);
    }

    pub fn watchImported(self: *ManagedPlan, allocator: std.mem.Allocator, component_path: []const u8, name: []const u8, binding: []const u8, publisher_backed: bool) !void {
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

    pub fn selectLocal(self: *ManagedPlan, allocator: std.mem.Allocator, component_path: []const u8, name: []const u8) !void {
        for (self.locals.items) |item| if (std.mem.eql(u8, item.component_path, component_path) and std.mem.eql(u8, item.name, name)) return;
        const owned_path = try allocator.dupe(u8, component_path);
        errdefer allocator.free(owned_path);
        const owned_name = try allocator.dupe(u8, name);
        errdefer allocator.free(owned_name);
        try self.locals.append(allocator, .{ .component_path = owned_path, .name = owned_name });
    }

    pub fn select(self: *ManagedPlan, allocator: std.mem.Allocator, module_path: []const u8, name: []const u8, component_path: []const u8, binding: []const u8) !void {
        return self.selectMode(allocator, module_path, name, component_path, binding, true);
    }

    pub fn normalize(self: *ManagedPlan, allocator: std.mem.Allocator, module_path: []const u8, name: []const u8, component_path: []const u8) !void {
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
