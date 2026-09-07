const std = @import("std");
const entities = @import("module_semantic_entities.zig");
const primitives = @import("semantic_primitives.zig");

pub const Storage = struct {
    types: std.ArrayList(entities.ModuleType) = .empty,
    functions: std.ArrayList(entities.Function) = .empty,
    bindings: std.ArrayList(entities.Binding) = .empty,
    nodes: std.ArrayList(entities.ModuleNode) = .empty,
    blocks: std.ArrayList(entities.Block) = .empty,
    fields: std.ArrayList(entities.Field) = .empty,
    variants: std.ArrayList(entities.ChoiceVariant) = .empty,
    generic_arguments: std.ArrayList(entities.GenericArgument) = .empty,
    value_fields: std.ArrayList(entities.ValueField) = .empty,
    switch_cases: std.ArrayList(entities.SwitchCase) = .empty,
    switches: std.ArrayList(entities.Switch) = .empty,
    auto_deinit_fields: std.ArrayList(entities.AutoDeinitField) = .empty,
    auto_deinits: std.ArrayList(entities.AutoDeinit) = .empty,
    virtual_registries: std.ArrayList(entities.VirtualMethodRegistry) = .empty,
    virtualizes: std.ArrayList(entities.Virtualize) = .empty,
    virtual_calls: std.ArrayList(entities.VirtualCall) = .empty,
    reach_segments: std.ArrayList(primitives.StringRange) = .empty,
    reach_alternatives: std.ArrayList(entities.ReachAlternative) = .empty,
    reaches: std.ArrayList(entities.Reach) = .empty,
    nullable_unwraps: std.ArrayList(entities.NullableUnwrap) = .empty,
    testing_expect_errors: std.ArrayList(entities.TestingExpectError) = .empty,
    error_propagations: std.ArrayList(entities.ErrorPropagation) = .empty,
    error_contexts: std.ArrayList(entities.ErrorContext) = .empty,

    scopes: std.ArrayList(entities.Scope) = .empty,
    external_refs: std.ArrayList(entities.ExternalRef) = .empty,
    pending_operations: std.ArrayList(entities.PendingOperation) = .empty,

    node_refs: std.ArrayList(entities.ModuleNodeId) = .empty,
    type_refs: std.ArrayList(entities.ModuleTypeId) = .empty,
    binding_refs: std.ArrayList(entities.ModuleBindingId) = .empty,
    function_refs: std.ArrayList(entities.ModuleFunctionId) = .empty,
    virtual_registry_refs: std.ArrayList(entities.ModuleVirtualRegistryId) = .empty,
    roots: std.ArrayList(entities.ModuleNodeId) = .empty,

    pub fn deinit(self: *Storage, allocator: std.mem.Allocator) void {
        self.types.deinit(allocator);
        self.functions.deinit(allocator);
        self.bindings.deinit(allocator);
        self.nodes.deinit(allocator);
        self.blocks.deinit(allocator);
        self.fields.deinit(allocator);
        self.variants.deinit(allocator);
        self.generic_arguments.deinit(allocator);
        self.value_fields.deinit(allocator);
        self.switch_cases.deinit(allocator);
        self.switches.deinit(allocator);
        self.auto_deinit_fields.deinit(allocator);
        self.auto_deinits.deinit(allocator);
        self.virtual_registries.deinit(allocator);
        self.virtualizes.deinit(allocator);
        self.virtual_calls.deinit(allocator);
        self.reach_segments.deinit(allocator);
        self.reach_alternatives.deinit(allocator);
        self.reaches.deinit(allocator);
        self.nullable_unwraps.deinit(allocator);
        self.testing_expect_errors.deinit(allocator);
        self.error_propagations.deinit(allocator);
        self.error_contexts.deinit(allocator);
        self.scopes.deinit(allocator);
        self.external_refs.deinit(allocator);
        self.pending_operations.deinit(allocator);
        self.node_refs.deinit(allocator);
        self.type_refs.deinit(allocator);
        self.binding_refs.deinit(allocator);
        self.function_refs.deinit(allocator);
        self.virtual_registry_refs.deinit(allocator);
        self.roots.deinit(allocator);
        self.* = .{};
    }

    pub fn storageBytes(self: *const Storage) usize {
        return self.types.items.len * @sizeOf(entities.ModuleType) +
            self.functions.items.len * @sizeOf(entities.Function) +
            self.bindings.items.len * @sizeOf(entities.Binding) +
            self.nodes.items.len * @sizeOf(entities.ModuleNode) +
            self.blocks.items.len * @sizeOf(entities.Block) +
            self.fields.items.len * @sizeOf(entities.Field) +
            self.variants.items.len * @sizeOf(entities.ChoiceVariant) +
            self.generic_arguments.items.len * @sizeOf(entities.GenericArgument) +
            self.value_fields.items.len * @sizeOf(entities.ValueField) +
            self.switch_cases.items.len * @sizeOf(entities.SwitchCase) +
            self.switches.items.len * @sizeOf(entities.Switch) +
            self.auto_deinit_fields.items.len * @sizeOf(entities.AutoDeinitField) +
            self.auto_deinits.items.len * @sizeOf(entities.AutoDeinit) +
            self.virtual_registries.items.len * @sizeOf(entities.VirtualMethodRegistry) +
            self.virtualizes.items.len * @sizeOf(entities.Virtualize) +
            self.virtual_calls.items.len * @sizeOf(entities.VirtualCall) +
            self.reach_segments.items.len * @sizeOf(primitives.StringRange) +
            self.reach_alternatives.items.len * @sizeOf(entities.ReachAlternative) +
            self.reaches.items.len * @sizeOf(entities.Reach) +
            self.nullable_unwraps.items.len * @sizeOf(entities.NullableUnwrap) +
            self.testing_expect_errors.items.len * @sizeOf(entities.TestingExpectError) +
            self.error_propagations.items.len * @sizeOf(entities.ErrorPropagation) +
            self.error_contexts.items.len * @sizeOf(entities.ErrorContext) +
            self.scopes.items.len * @sizeOf(entities.Scope) +
            self.external_refs.items.len * @sizeOf(entities.ExternalRef) +
            self.pending_operations.items.len * @sizeOf(entities.PendingOperation) +
            self.node_refs.items.len * @sizeOf(entities.ModuleNodeId) +
            self.type_refs.items.len * @sizeOf(entities.ModuleTypeId) +
            self.binding_refs.items.len * @sizeOf(entities.ModuleBindingId) +
            self.function_refs.items.len * @sizeOf(entities.ModuleFunctionId) +
            self.virtual_registry_refs.items.len * @sizeOf(entities.ModuleVirtualRegistryId) +
            self.roots.items.len * @sizeOf(entities.ModuleNodeId);
    }
};

test "module semantic storage owns resolved and pending tables" {
    const allocator = std.testing.allocator;
    var storage: Storage = .{};
    defer storage.deinit(allocator);

    try storage.types.append(allocator, .{ .builtin = .Int32 });
    try storage.external_refs.append(allocator, .{
        .kind = .function,
        .module_path = null,
        .name = .{ .start = 0, .len = 3 },
        .source = .{ .file_index = 0, .offset = 5 },
    });
    try std.testing.expect(storage.storageBytes() >= @sizeOf(entities.ModuleType));
    try std.testing.expectEqual(@as(usize, 1), storage.external_refs.items.len);
}
