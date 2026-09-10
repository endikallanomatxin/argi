const std = @import("std");
const module_sg = @import("module_semantic_graph.zig");
const module_entities = @import("module_semantic_entities.zig");
const global_sg = @import("global_semantic_graph.zig");
const globalizer = @import("semantic_globalizer.zig");

/// Temporary construction state for globally-dependent binding types.
/// The pending control operation is the single source of truth; this helper is
/// removed once binding partiality is represented directly in the semantic IR.
pub const State = struct {
    unresolved: []bool,

    pub fn init(
        allocator: std.mem.Allocator,
        graph: *global_sg.GlobalSemanticGraph,
        modules: []const module_sg.ModuleSemanticGraph,
        offsets: []const globalizer.Offsets,
    ) !State {
        const unresolved = try allocator.alloc(bool, graph.bindings.items.len);
        errdefer allocator.free(unresolved);
        @memset(unresolved, false);
        var result = State{ .unresolved = unresolved };
        try result.markModuleBindings(modules, offsets);
        result.hideProvisionalNodeTypes(graph);
        return result;
    }

    pub fn deinit(self: *State, allocator: std.mem.Allocator) void {
        allocator.free(self.unresolved);
        self.* = undefined;
    }

    pub fn isUnresolved(self: *const State, binding: global_sg.GlobalBindingId) bool {
        const raw: usize = @intFromEnum(binding);
        return raw < self.unresolved.len and self.unresolved[raw];
    }

    pub fn operationResolved(
        self: *State,
        module: *const module_sg.ModuleSemanticGraph,
        o: globalizer.Offsets,
        operation: module_entities.PendingOperation,
    ) void {
        switch (operation) {
            .resolve_for_each => |value| self.markResolved(globalizer.globalBinding(o, value.binding)),
            .resolve_match => |value| self.markMatchBindingsResolved(module, o, value),
            else => {},
        }
    }

    pub fn finish(self: *const State) !void {
        for (self.unresolved) |value| if (value) return error.UnresolvedGlobalBindingTypes;
    }

    fn markModuleBindings(
        self: *State,
        modules: []const module_sg.ModuleSemanticGraph,
        offsets: []const globalizer.Offsets,
    ) !void {
        if (modules.len != offsets.len) return error.InvalidGlobalBindingResolutionOffsets;
        for (modules, 0..) |*module, module_index| {
            const o = offsets[module_index];
            for (module.semantic.pending_operations.items) |operation| switch (operation) {
                .resolve_for_each => |value| try self.markUnresolved(globalizer.globalBinding(o, value.binding)),
                .resolve_match_case => |value| if (value.payload_binding) |binding|
                    try self.markUnresolved(globalizer.globalBinding(o, binding)),
                else => {},
            };
        }
    }

    fn hideProvisionalNodeTypes(self: *const State, graph: *global_sg.GlobalSemanticGraph) void {
        var changed = true;
        while (changed) {
            changed = false;
            for (graph.nodes.items) |*node| switch (node.content) {
                .binding_use => |binding| if (self.isUnresolved(binding) and node.ty != null) {
                    node.ty = null;
                    changed = true;
                },
                .assignment => |assignment| if (self.isUnresolved(assignment.binding) and node.ty != null) {
                    node.ty = null;
                    changed = true;
                },
                .move_value => |source| if (graph.nodes.items[@intFromEnum(source)].ty == null and node.ty != null) {
                    node.ty = null;
                    changed = true;
                },
                else => {},
            };
        }
    }

    fn markMatchBindingsResolved(self: *State, module: *const module_sg.ModuleSemanticGraph, o: globalizer.Offsets, match: anytype) void {
        const cases = module.semantic.node_refs.items[match.cases.start..][0..match.cases.len];
        for (cases) |case_node| switch (module.semantic.nodes.items[@intFromEnum(case_node)]) {
            .pending => |pending_id| switch (module.semantic.pending_operations.items[@intFromEnum(pending_id)]) {
                .resolve_match_case => |case| if (case.payload_binding) |binding|
                    self.markResolved(globalizer.globalBinding(o, binding)),
                else => {},
            },
            .resolved => {},
        };
    }

    fn markUnresolved(self: *State, binding: global_sg.GlobalBindingId) !void {
        const raw: usize = @intFromEnum(binding);
        if (raw >= self.unresolved.len) return error.InvalidUnresolvedGlobalBinding;
        self.unresolved[raw] = true;
    }

    fn markResolved(self: *State, binding: global_sg.GlobalBindingId) void {
        const raw: usize = @intFromEnum(binding);
        std.debug.assert(raw < self.unresolved.len);
        self.unresolved[raw] = false;
    }
};

test "binding resolution state distinguishes construction from language Any" {
    const allocator = std.testing.allocator;
    var graph: global_sg.GlobalSemanticGraph = .{};
    defer graph.deinit(allocator);

    try graph.bindings.append(allocator, .{
        .name = .{ .start = 0, .len = 0 },
        .source = .{ .file_index = 0, .offset = 0 },
        .ty = @enumFromInt(0),
        .mutability = .constant,
    });
    var state = State{ .unresolved = try allocator.alloc(bool, 1) };
    defer state.deinit(allocator);
    state.unresolved[0] = true;

    try std.testing.expect(state.isUnresolved(@enumFromInt(0)));
    try std.testing.expectError(error.UnresolvedGlobalBindingTypes, state.finish());
    state.markResolved(@enumFromInt(0));
    try state.finish();
}
