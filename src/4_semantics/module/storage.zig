const std = @import("std");
const entities = @import("entities.zig");
const parameterized_storage = @import("parameterized/storage.zig");
const primitives = @import("../primitives/schema.zig");
const type_shapes = @import("../primitives/type_shapes.zig");

/// Canonical module-owned semantic pools. IDs remain stable as construction
/// appends types, fields, variants and executable entities.
pub const Storage = struct {
    local_semantics_complete: bool = false,

    declaration_bindings: std.ArrayList(entities.DeclarationBinding) = .empty,
    module_aliases: std.ArrayList(entities.ModuleAlias) = .empty,

    /// Canonical pools shared by discovery and subsequent lowering.
    fields: std.ArrayList(entities.Field) = .empty,
    variants: std.ArrayList(entities.ChoiceVariant) = .empty,
    /// One canonical pool shared by discovery and subsequent lowering.
    generic_arguments: std.ArrayList(entities.GenericArgument) = .empty,
    types: std.ArrayList(entities.ModuleType) = .empty,
    type_definitions: std.ArrayList(entities.TypeDefinition) = .empty,
    family_definitions: std.ArrayList(entities.FamilyDefinition) = .empty,

    generic_instances: std.ArrayList(type_shapes.GenericInstance(entities.Ids)) = .empty,

    bindings: std.ArrayList(entities.Binding) = .empty,
    /// Sparse construction state: bindings whose semantic type is not known
    /// until GlobalSema resolves an initializer/control-flow dependency.
    unresolved_binding_types: std.ArrayList(entities.ModuleBindingId) = .empty,
    nodes: std.ArrayList(entities.ModuleNode) = .empty,
    comptime_requests: std.ArrayList(entities.ModuleNodeId) = .empty,
    blocks: std.ArrayList(entities.Block) = .empty,
    block_assumptions: std.ArrayList(entities.BlockAssumptions) = .empty,
    value_fields: std.ArrayList(entities.ValueField) = .empty,
    switch_cases: std.ArrayList(entities.SwitchCase) = .empty,
    switches: std.ArrayList(entities.Switch) = .empty,
    auto_deinit_fields: std.ArrayList(entities.AutoDeinitField) = .empty,
    auto_deinits: std.ArrayList(entities.AutoDeinit) = .empty,
    virtual_registries: std.ArrayList(entities.VirtualMethodRegistry) = .empty,
    virtualizes: std.ArrayList(entities.Virtualize) = .empty,
    virtual_calls: std.ArrayList(entities.VirtualCall) = .empty,
    nullable_unwraps: std.ArrayList(entities.NullableUnwrap) = .empty,
    error_propagations: std.ArrayList(entities.ErrorPropagation) = .empty,

    parameterized_storage: parameterized_storage.Storage = .{},

    scopes: std.ArrayList(entities.Scope) = .empty,
    external_refs: std.ArrayList(entities.ExternalRef) = .empty,
    pending_operations: std.ArrayList(entities.PendingOperation) = .empty,
    /// Function owning each pending operation, or null for module/interface
    /// construction work that is always active.
    pending_owner_functions: std.ArrayList(?entities.ModuleFunctionId) = .empty,

    node_refs: std.ArrayList(entities.ModuleNodeId) = .empty,
    type_refs: std.ArrayList(entities.ModuleTypeId) = .empty,
    binding_refs: std.ArrayList(entities.ModuleBindingId) = .empty,
    function_refs: std.ArrayList(entities.ModuleFunctionId) = .empty,
    virtual_registry_refs: std.ArrayList(entities.ModuleVirtualRegistryId) = .empty,
    roots: std.ArrayList(entities.ModuleNodeId) = .empty,

    pub fn deinit(self: *Storage, allocator: std.mem.Allocator) void {
        self.declaration_bindings.deinit(allocator);
        self.module_aliases.deinit(allocator);
        self.fields.deinit(allocator);
        self.variants.deinit(allocator);
        self.generic_arguments.deinit(allocator);
        self.types.deinit(allocator);
        self.type_definitions.deinit(allocator);
        self.family_definitions.deinit(allocator);
        self.generic_instances.deinit(allocator);
        self.bindings.deinit(allocator);
        self.unresolved_binding_types.deinit(allocator);
        self.nodes.deinit(allocator);
        self.comptime_requests.deinit(allocator);
        self.blocks.deinit(allocator);
        self.block_assumptions.deinit(allocator);
        self.value_fields.deinit(allocator);
        self.switch_cases.deinit(allocator);
        self.switches.deinit(allocator);
        self.auto_deinit_fields.deinit(allocator);
        self.auto_deinits.deinit(allocator);
        self.virtual_registries.deinit(allocator);
        self.virtualizes.deinit(allocator);
        self.virtual_calls.deinit(allocator);
        self.nullable_unwraps.deinit(allocator);
        self.error_propagations.deinit(allocator);
        self.parameterized_storage.deinit(allocator);
        self.scopes.deinit(allocator);
        self.external_refs.deinit(allocator);
        self.pending_operations.deinit(allocator);
        self.pending_owner_functions.deinit(allocator);
        self.node_refs.deinit(allocator);
        self.type_refs.deinit(allocator);
        self.binding_refs.deinit(allocator);
        self.function_refs.deinit(allocator);
        self.virtual_registry_refs.deinit(allocator);
        self.roots.deinit(allocator);
        self.* = .{};
    }

    pub fn storageBytes(self: *const Storage) usize {
        return @sizeOf(bool) +
            self.declaration_bindings.items.len * @sizeOf(entities.DeclarationBinding) +
            self.module_aliases.items.len * @sizeOf(entities.ModuleAlias) +
            self.fields.items.len * @sizeOf(entities.Field) +
            self.variants.items.len * @sizeOf(entities.ChoiceVariant) +
            self.generic_arguments.items.len * @sizeOf(entities.GenericArgument) +
            self.types.items.len * @sizeOf(entities.ModuleType) +
            self.type_definitions.items.len * @sizeOf(entities.TypeDefinition) +
            self.family_definitions.items.len * @sizeOf(entities.FamilyDefinition) +
            self.generic_instances.items.len * @sizeOf(type_shapes.GenericInstance(entities.Ids)) +
            self.bindings.items.len * @sizeOf(entities.Binding) +
            self.unresolved_binding_types.items.len * @sizeOf(entities.ModuleBindingId) +
            self.nodes.items.len * @sizeOf(entities.ModuleNode) +
            self.comptime_requests.items.len * @sizeOf(entities.ModuleNodeId) +
            self.blocks.items.len * @sizeOf(entities.Block) +
            self.block_assumptions.items.len * @sizeOf(entities.BlockAssumptions) +
            self.value_fields.items.len * @sizeOf(entities.ValueField) +
            self.switch_cases.items.len * @sizeOf(entities.SwitchCase) +
            self.switches.items.len * @sizeOf(entities.Switch) +
            self.auto_deinit_fields.items.len * @sizeOf(entities.AutoDeinitField) +
            self.auto_deinits.items.len * @sizeOf(entities.AutoDeinit) +
            self.virtual_registries.items.len * @sizeOf(entities.VirtualMethodRegistry) +
            self.virtualizes.items.len * @sizeOf(entities.Virtualize) +
            self.virtual_calls.items.len * @sizeOf(entities.VirtualCall) +
            self.nullable_unwraps.items.len * @sizeOf(entities.NullableUnwrap) +
            self.error_propagations.items.len * @sizeOf(entities.ErrorPropagation) +
            self.parameterized_storage.storageBytes() +
            self.scopes.items.len * @sizeOf(entities.Scope) +
            self.external_refs.items.len * @sizeOf(entities.ExternalRef) +
            self.pending_operations.items.len * @sizeOf(entities.PendingOperation) +
            self.pending_owner_functions.items.len * @sizeOf(?entities.ModuleFunctionId) +
            self.node_refs.items.len * @sizeOf(entities.ModuleNodeId) +
            self.type_refs.items.len * @sizeOf(entities.ModuleTypeId) +
            self.binding_refs.items.len * @sizeOf(entities.ModuleBindingId) +
            self.function_refs.items.len * @sizeOf(entities.ModuleFunctionId) +
            self.virtual_registry_refs.items.len * @sizeOf(entities.ModuleVirtualRegistryId) +
            self.roots.items.len * @sizeOf(entities.ModuleNodeId);
    }
};

test "module semantic storage owns cold declaration binding links" {
    const allocator = std.testing.allocator;
    var storage: Storage = .{};
    defer storage.deinit(allocator);

    try std.testing.expect(!storage.local_semantics_complete);
    try storage.declaration_bindings.append(allocator, .{ .declaration = @enumFromInt(1), .binding = @enumFromInt(2) });
    try storage.types.append(allocator, .{ .resolved = .{ .builtin = .Int32 } });
    try storage.types.append(allocator, .{ .external = @enumFromInt(0) });
    try storage.types.append(allocator, .{ .resolved = .{ .pointer = .{
        .child = @enumFromInt(1),
        .mutability = .read_only,
    } } });
    try std.testing.expectEqual(@as(u32, 2), @intFromEnum(storage.declaration_bindings.items[0].binding));
    try std.testing.expectEqual(@as(usize, 3), storage.types.items.len);
}
