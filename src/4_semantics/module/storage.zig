const std = @import("std");
const entities = @import("entities.zig");
const parameterized_storage = @import("parameterized/storage.zig");
const primitives = @import("../primitives/schema.zig");
const callable = @import("../primitives/callable.zig");
const type_shapes = @import("../primitives/type_shapes.zig");

/// Frozen sizes of the migration-era prefixes that precede canonical Module*
/// identities. Once canonical lowering starts these prefixes must never grow:
/// doing so would shift every already-issued logical ID.
pub const CompatibilityBases = struct {
    types: u32,
    fields: u32,
    variants: u32,
    generic_arguments: u32,
};

pub const Storage = struct {
    local_semantics_complete: bool = false,
    compatibility_bases: ?CompatibilityBases = null,

    declaration_semantics: std.ArrayList(entities.DeclarationSemantic) = .empty,
    declaration_bindings: std.ArrayList(entities.DeclarationBinding) = .empty,
    module_aliases: std.ArrayList(entities.ModuleAlias) = .empty,
    function_semantics: std.ArrayList(entities.FunctionSemantic) = .empty,
    /// Aligned with ModuleSemanticGraph.functions. `null` is a normal named
    /// function; non-null is the semantic overload operator identity.
    function_operators: std.ArrayList(?callable.OperatorKind) = .empty,
    field_semantics: std.ArrayList(entities.FieldSemantic) = .empty,
    variant_semantics: std.ArrayList(entities.VariantSemantic) = .empty,

    /// Canonical semantic tails appended after the remaining builder-era
    /// prefixes owned by ModuleSemanticGraph itself.
    fields: std.ArrayList(entities.Field) = .empty,
    variants: std.ArrayList(entities.ChoiceVariant) = .empty,
    generic_arguments: std.ArrayList(entities.GenericArgument) = .empty,
    types: std.ArrayList(entities.ModuleType) = .empty,

    generic_instances: std.ArrayList(type_shapes.GenericInstance(entities.Ids)) = .empty,

    bindings: std.ArrayList(entities.Binding) = .empty,
    /// Sparse construction state: bindings whose semantic type is not known
    /// until GlobalSema resolves an initializer/control-flow dependency.
    unresolved_binding_types: std.ArrayList(entities.ModuleBindingId) = .empty,
    nodes: std.ArrayList(entities.ModuleNode) = .empty,
    blocks: std.ArrayList(entities.Block) = .empty,
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

    parameterized_storage: parameterized_storage.Storage = .{},

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
        self.declaration_semantics.deinit(allocator);
        self.declaration_bindings.deinit(allocator);
        self.module_aliases.deinit(allocator);
        self.function_semantics.deinit(allocator);
        self.function_operators.deinit(allocator);
        self.field_semantics.deinit(allocator);
        self.variant_semantics.deinit(allocator);
        self.fields.deinit(allocator);
        self.variants.deinit(allocator);
        self.generic_arguments.deinit(allocator);
        self.types.deinit(allocator);
        self.generic_instances.deinit(allocator);
        self.bindings.deinit(allocator);
        self.unresolved_binding_types.deinit(allocator);
        self.nodes.deinit(allocator);
        self.blocks.deinit(allocator);
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
        self.parameterized_storage.deinit(allocator);
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
        return @sizeOf(bool) + @sizeOf(?CompatibilityBases) +
            self.declaration_semantics.items.len * @sizeOf(entities.DeclarationSemantic) +
            self.declaration_bindings.items.len * @sizeOf(entities.DeclarationBinding) +
            self.module_aliases.items.len * @sizeOf(entities.ModuleAlias) +
            self.function_semantics.items.len * @sizeOf(entities.FunctionSemantic) +
            self.function_operators.items.len * @sizeOf(?callable.OperatorKind) +
            self.field_semantics.items.len * @sizeOf(entities.FieldSemantic) +
            self.variant_semantics.items.len * @sizeOf(entities.VariantSemantic) +
            self.fields.items.len * @sizeOf(entities.Field) +
            self.variants.items.len * @sizeOf(entities.ChoiceVariant) +
            self.generic_arguments.items.len * @sizeOf(entities.GenericArgument) +
            self.types.items.len * @sizeOf(entities.ModuleType) +
            self.generic_instances.items.len * @sizeOf(type_shapes.GenericInstance(entities.Ids)) +
            self.bindings.items.len * @sizeOf(entities.Binding) +
            self.unresolved_binding_types.items.len * @sizeOf(entities.ModuleBindingId) +
            self.nodes.items.len * @sizeOf(entities.ModuleNode) +
            self.blocks.items.len * @sizeOf(entities.Block) +
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
            self.parameterized_storage.storageBytes() +
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
