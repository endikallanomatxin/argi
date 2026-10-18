const std = @import("std");
const g = @import("../4_semantics/global/graph.zig");
const types = @import("../4_semantics/global/types.zig");

/// Backend-independent order for constant module initializers. No language
/// operations execute here. Address dependencies also require initialization,
/// matching native constant emission and preventing cycles through erasure.
pub const Plan = struct {
    order: []const g.GlobalBindingId,
};

pub fn build(allocator: std.mem.Allocator, graph: *const g.GlobalSemanticGraph, roots: []const g.GlobalBindingId) !Plan {
    var failure: ?g.GlobalBindingId = null;
    return buildReporting(allocator, graph, roots, &failure);
}

pub fn buildReporting(allocator: std.mem.Allocator, graph: *const g.GlobalSemanticGraph, roots: []const g.GlobalBindingId, failure: *?g.GlobalBindingId) !Plan {
    failure.* = null;
    const states = try allocator.alloc(Visit, graph.bindings.items.len);
    defer allocator.free(states);
    @memset(states, .local);
    for (graph.roots.items) |root| {
        const node = graph.node(root);
        if (node.content == .binding_declaration) states[@intFromEnum(node.content.binding_declaration)] = .pending;
    }
    var state: State = .{ .allocator = allocator, .graph = graph, .states = states, .failure = failure };
    errdefer state.order.deinit(allocator);
    for (roots) |root| try state.binding(root);
    return .{ .order = try state.order.toOwnedSlice(allocator) };
}

const Visit = enum(u8) { local, pending, active, done };

const State = struct {
    allocator: std.mem.Allocator,
    graph: *const g.GlobalSemanticGraph,
    states: []Visit,
    failure: *?g.GlobalBindingId,
    active: usize = 0,
    order: std.ArrayList(g.GlobalBindingId) = .empty,

    fn binding(self: *State, id: g.GlobalBindingId) anyerror!void {
        errdefer if (self.failure.* == null) {
            self.failure.* = id;
        };
        if (@intFromEnum(id) >= self.graph.bindings.items.len) return error.InvalidGlobalInitializer;
        const state = &self.states[@intFromEnum(id)];
        switch (state.*) {
            .done => return,
            .active => return error.CyclicGlobalInitializer,
            .local => return error.InvalidGlobalInitializer,
            .pending => {},
        }
        if (self.active >= 256) return error.InvalidGlobalInitializer;
        self.active += 1;
        defer self.active -= 1;
        state.* = .active;
        if (self.graph.binding(id).initialization) |node| try self.value(node, 0);
        state.* = .done;
        try self.order.append(self.allocator, id);
    }

    fn value(self: *State, id: g.GlobalNodeId, depth: usize) anyerror!void {
        if (depth > 256 or @intFromEnum(id) >= self.graph.nodes.items.len) return error.InvalidGlobalInitializer;
        const node = self.graph.node(id);
        switch (node.content) {
            .int_literal, .float_literal, .char_literal, .bool_literal, .string_literal => {},
            .binding_use => |binding_id| try self.binding(binding_id),
            .binary_operation => |operation| {
                try self.value(operation.left, depth + 1);
                try self.value(operation.right, depth + 1);
            },
            .address_of => |target| {
                const addressed = self.graph.node(target);
                if (addressed.content != .binding_use) return error.InvalidGlobalInitializer;
                try self.binding(addressed.content.binding_use);
            },
            .virtualize => |index| try self.value(self.graph.virtualizes.items[@intFromEnum(index)].value, depth + 1),
            .struct_value_literal => |literal| {
                const fields = types.fields(self.graph, node.ty orelse return error.InvalidGlobalInitializer) orelse return error.InvalidGlobalInitializer;
                for (self.graph.fields.items[fields.start..][0..fields.len]) |field| {
                    var initializer = field.default_value;
                    for (self.graph.value_fields.items[literal.fields.start..][0..literal.fields.len]) |supplied| {
                        if (std.mem.eql(u8, self.graph.text(field.name), self.graph.text(supplied.name))) initializer = supplied.value;
                    }
                    if (initializer) |child| try self.value(child, depth + 1);
                }
            },
            else => return error.NonConstantGlobalInitializer,
        }
    }
};

test "global initializer plans order dependencies and reject cycles" {
    const a = std.testing.allocator;
    var graph: g.GlobalSemanticGraph = .{};
    defer graph.deinit(a);
    const source = @import("../4_semantics/primitives/schema.zig").SourceRef{ .file_index = 0, .offset = 0 };
    try graph.types.append(a, .{ .builtin = .Int32 });
    for (0..2) |index| {
        try graph.bindings.append(a, .{ .name = try graph.addString(a, if (index == 0) "first" else "second"), .ty = @enumFromInt(0), .mutability = .variable, .source = source, .initialization = @enumFromInt(@as(u32, @intCast(index))) });
        try graph.roots.append(a, @enumFromInt(@as(u32, @intCast(index + 2))));
    }
    try graph.nodes.appendSlice(a, &.{
        .{ .source = source, .ty = @enumFromInt(0), .content = .{ .binding_use = @enumFromInt(1) } },
        .{ .source = source, .ty = @enumFromInt(0), .content = .{ .int_literal = 42 } },
        .{ .source = source, .ty = null, .content = .{ .binding_declaration = @enumFromInt(0) } },
        .{ .source = source, .ty = null, .content = .{ .binding_declaration = @enumFromInt(1) } },
    });
    const plan = try build(a, &graph, &.{@enumFromInt(0)});
    defer a.free(plan.order);
    try std.testing.expectEqualSlices(g.GlobalBindingId, &.{ @enumFromInt(1), @enumFromInt(0) }, plan.order);
    graph.nodes.items[1].content = .{ .binding_use = @enumFromInt(0) };
    var failure: ?g.GlobalBindingId = null;
    try std.testing.expectError(error.CyclicGlobalInitializer, buildReporting(a, &graph, &.{@enumFromInt(0)}, &failure));
    try std.testing.expectEqual(@as(?g.GlobalBindingId, @enumFromInt(0)), failure);
    graph.nodes.items[1].content = .abort_statement;
    try std.testing.expectError(error.NonConstantGlobalInitializer, buildReporting(a, &graph, &.{@enumFromInt(0)}, &failure));
    try std.testing.expectEqual(@as(?g.GlobalBindingId, @enumFromInt(1)), failure);
}
