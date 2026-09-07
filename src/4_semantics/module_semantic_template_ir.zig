const std = @import("std");
const entities = @import("module_semantic_entities.zig");
const primitives = @import("semantic_primitives.zig");

pub const TemplateParameterId = enum(u32) { _ };
pub const TemplateTypeId = enum(u32) { _ };
pub const TemplateDeclId = enum(u32) { _ };
pub const TemplateFunctionId = enum(u32) { _ };
pub const TemplateBindingId = enum(u32) { _ };
pub const TemplateNodeId = enum(u32) { _ };
pub const TemplateBlockId = enum(u32) { _ };
pub const TemplateFieldId = enum(u32) { _ };
pub const TemplateVariantId = enum(u32) { _ };
pub const TemplateGenericArgId = enum(u32) { _ };
pub const TemplateValueFieldId = enum(u32) { _ };
pub const TemplateSwitchCaseId = enum(u32) { _ };
pub const TemplateSwitchId = enum(u32) { _ };
pub const TemplateAutoDeinitFieldId = enum(u32) { _ };
pub const TemplateAutoDeinitId = enum(u32) { _ };
pub const TemplateVirtualRegistryId = enum(u32) { _ };
pub const TemplateVirtualizeId = enum(u32) { _ };
pub const TemplateVirtualCallId = enum(u32) { _ };
pub const TemplateReachSegmentId = enum(u32) { _ };
pub const TemplateReachAlternativeId = enum(u32) { _ };
pub const TemplateReachId = enum(u32) { _ };
pub const TemplateNullableUnwrapId = enum(u32) { _ };
pub const TemplateTestingExpectErrorId = enum(u32) { _ };
pub const TemplateErrorPropagationId = enum(u32) { _ };
pub const TemplateErrorContextId = enum(u32) { _ };
pub const TemplatePendingId = enum(u32) { _ };

pub const Ids = struct {
    pub const DeclId = TemplateDeclId;
    pub const TypeId = TemplateTypeId;
    pub const FunctionId = TemplateFunctionId;
    pub const BindingId = TemplateBindingId;
    pub const NodeId = TemplateNodeId;
    pub const BlockId = TemplateBlockId;
    pub const FieldId = TemplateFieldId;
    pub const VariantId = TemplateVariantId;
    pub const GenericArgId = TemplateGenericArgId;
    pub const ValueFieldId = TemplateValueFieldId;
    pub const SwitchCaseId = TemplateSwitchCaseId;
    pub const SwitchId = TemplateSwitchId;
    pub const AutoDeinitFieldId = TemplateAutoDeinitFieldId;
    pub const AutoDeinitId = TemplateAutoDeinitId;
    pub const VirtualRegistryId = TemplateVirtualRegistryId;
    pub const VirtualizeId = TemplateVirtualizeId;
    pub const VirtualCallId = TemplateVirtualCallId;
    pub const ReachSegmentId = TemplateReachSegmentId;
    pub const ReachAlternativeId = TemplateReachAlternativeId;
    pub const ReachId = TemplateReachId;
    pub const NullableUnwrapId = TemplateNullableUnwrapId;
    pub const TestingExpectErrorId = TemplateTestingExpectErrorId;
    pub const ErrorPropagationId = TemplateErrorPropagationId;
    pub const ErrorContextId = TemplateErrorContextId;
};

pub const DeclarationRef = union(enum) {
    module: entities.ModuleDeclId,
    external: entities.ExternalRefId,
};

pub const FunctionRef = union(enum) {
    module: entities.ModuleFunctionId,
    external: entities.ExternalRefId,
};

pub const VariantRef = union(enum) {
    module: entities.ModuleVariantId,
    external: entities.ExternalRefId,
};

/// A template type is self-contained in the ModuleSG. Concrete module types are
/// referenced directly; placeholders and composite template shapes stay in the
/// template ID domain until instantiation substitutes them.
pub const Type = union(enum) {
    concrete: entities.ModuleTypeId,
    parameter: TemplateParameterId,
    external: entities.ExternalRefId,
    resolved: primitives.SemanticType(Ids),
};

pub const Decl = struct { target: DeclarationRef };
pub const Function = struct { target: FunctionRef };
pub const Variant = struct { target: VariantRef };

pub const Field = primitives.Field(Ids);
pub const GenericArgument = primitives.GenericArgument(Ids);
pub const Binding = primitives.Binding(Ids);
pub const Block = primitives.Block(Ids);
pub const ValueField = primitives.ValueField(Ids);
pub const SwitchCase = primitives.SwitchCase(Ids);
pub const Switch = primitives.Switch(Ids);
pub const AutoDeinitField = primitives.AutoDeinitField(Ids);
pub const AutoDeinit = primitives.AutoDeinit(Ids);
pub const VirtualMethodRegistry = primitives.VirtualMethodRegistry(Ids);
pub const Virtualize = primitives.Virtualize(Ids);
pub const VirtualCall = primitives.VirtualCall(Ids);
pub const ReachAlternative = primitives.ReachAlternative(Ids);
pub const Reach = primitives.Reach(Ids);
pub const NullableUnwrap = primitives.NullableUnwrap(Ids);
pub const TestingExpectError = primitives.TestingExpectError(Ids);
pub const ErrorPropagation = primitives.ErrorPropagation(Ids);
pub const ErrorContext = primitives.ErrorContext(Ids);
pub const ResolvedNode = primitives.Node(Ids);

/// Decisions intentionally deferred to template instantiation. These holes are
/// semantic, not syntax references, so a cached ModuleSG needs no FileST/source
/// to continue monomorphization.
pub const Pending = union(enum) {
    resolve_name: struct {
        name: primitives.StringRange,
        source: primitives.SourceRef,
    },
    resolve_call: struct {
        name: primitives.StringRange,
        input: TemplateNodeId,
        source: primitives.SourceRef,
    },
    resolve_field: struct {
        value: TemplateNodeId,
        field_name: primitives.StringRange,
        source: primitives.SourceRef,
    },
    resolve_copy: struct { value: TemplateNodeId },
    resolve_deinit: struct { binding: TemplateBindingId },
};

pub const Node = union(enum) {
    resolved: ResolvedNode,
    pending: TemplatePendingId,
};

pub const Storage = struct {
    types: std.ArrayList(Type) = .empty,
    declarations: std.ArrayList(Decl) = .empty,
    functions: std.ArrayList(Function) = .empty,
    variants: std.ArrayList(Variant) = .empty,
    fields: std.ArrayList(Field) = .empty,
    generic_arguments: std.ArrayList(GenericArgument) = .empty,
    bindings: std.ArrayList(Binding) = .empty,
    nodes: std.ArrayList(Node) = .empty,
    blocks: std.ArrayList(Block) = .empty,
    value_fields: std.ArrayList(ValueField) = .empty,
    switch_cases: std.ArrayList(SwitchCase) = .empty,
    switches: std.ArrayList(Switch) = .empty,
    auto_deinit_fields: std.ArrayList(AutoDeinitField) = .empty,
    auto_deinits: std.ArrayList(AutoDeinit) = .empty,
    virtual_registries: std.ArrayList(VirtualMethodRegistry) = .empty,
    virtualizes: std.ArrayList(Virtualize) = .empty,
    virtual_calls: std.ArrayList(VirtualCall) = .empty,
    reach_segments: std.ArrayList(primitives.StringRange) = .empty,
    reach_alternatives: std.ArrayList(ReachAlternative) = .empty,
    reaches: std.ArrayList(Reach) = .empty,
    nullable_unwraps: std.ArrayList(NullableUnwrap) = .empty,
    testing_expect_errors: std.ArrayList(TestingExpectError) = .empty,
    error_propagations: std.ArrayList(ErrorPropagation) = .empty,
    error_contexts: std.ArrayList(ErrorContext) = .empty,
    pending: std.ArrayList(Pending) = .empty,

    node_refs: std.ArrayList(TemplateNodeId) = .empty,
    type_refs: std.ArrayList(TemplateTypeId) = .empty,
    binding_refs: std.ArrayList(TemplateBindingId) = .empty,
    function_refs: std.ArrayList(TemplateFunctionId) = .empty,
    virtual_registry_refs: std.ArrayList(TemplateVirtualRegistryId) = .empty,

    pub fn deinit(self: *Storage, allocator: std.mem.Allocator) void {
        inline for (.{
            &self.types,
            &self.declarations,
            &self.functions,
            &self.variants,
            &self.fields,
            &self.generic_arguments,
            &self.bindings,
            &self.nodes,
            &self.blocks,
            &self.value_fields,
            &self.switch_cases,
            &self.switches,
            &self.auto_deinit_fields,
            &self.auto_deinits,
            &self.virtual_registries,
            &self.virtualizes,
            &self.virtual_calls,
            &self.reach_segments,
            &self.reach_alternatives,
            &self.reaches,
            &self.nullable_unwraps,
            &self.testing_expect_errors,
            &self.error_propagations,
            &self.error_contexts,
            &self.pending,
            &self.node_refs,
            &self.type_refs,
            &self.binding_refs,
            &self.function_refs,
            &self.virtual_registry_refs,
        }) |list| list.deinit(allocator);
        self.* = .{};
    }

    pub fn storageBytes(self: *const Storage) usize {
        return self.types.items.len * @sizeOf(Type) +
            self.declarations.items.len * @sizeOf(Decl) +
            self.functions.items.len * @sizeOf(Function) +
            self.variants.items.len * @sizeOf(Variant) +
            self.fields.items.len * @sizeOf(Field) +
            self.generic_arguments.items.len * @sizeOf(GenericArgument) +
            self.bindings.items.len * @sizeOf(Binding) +
            self.nodes.items.len * @sizeOf(Node) +
            self.blocks.items.len * @sizeOf(Block) +
            self.value_fields.items.len * @sizeOf(ValueField) +
            self.switch_cases.items.len * @sizeOf(SwitchCase) +
            self.switches.items.len * @sizeOf(Switch) +
            self.auto_deinit_fields.items.len * @sizeOf(AutoDeinitField) +
            self.auto_deinits.items.len * @sizeOf(AutoDeinit) +
            self.virtual_registries.items.len * @sizeOf(VirtualMethodRegistry) +
            self.virtualizes.items.len * @sizeOf(Virtualize) +
            self.virtual_calls.items.len * @sizeOf(VirtualCall) +
            self.reach_segments.items.len * @sizeOf(primitives.StringRange) +
            self.reach_alternatives.items.len * @sizeOf(ReachAlternative) +
            self.reaches.items.len * @sizeOf(Reach) +
            self.nullable_unwraps.items.len * @sizeOf(NullableUnwrap) +
            self.testing_expect_errors.items.len * @sizeOf(TestingExpectError) +
            self.error_propagations.items.len * @sizeOf(ErrorPropagation) +
            self.error_contexts.items.len * @sizeOf(ErrorContext) +
            self.pending.items.len * @sizeOf(Pending) +
            self.node_refs.items.len * @sizeOf(TemplateNodeId) +
            self.type_refs.items.len * @sizeOf(TemplateTypeId) +
            self.binding_refs.items.len * @sizeOf(TemplateBindingId) +
            self.function_refs.items.len * @sizeOf(TemplateFunctionId) +
            self.virtual_registry_refs.items.len * @sizeOf(TemplateVirtualRegistryId);
    }
};

test "template IR represents generic placeholders without syntax refs" {
    const allocator = std.testing.allocator;
    var storage: Storage = .{};
    defer storage.deinit(allocator);

    try storage.types.append(allocator, .{ .parameter = @enumFromInt(0) });
    try storage.nodes.append(allocator, .{ .pending = @enumFromInt(0) });
    try storage.pending.append(allocator, .{ .resolve_name = .{
        .name = .{ .start = 0, .len = 1 },
        .source = .{ .file_index = 0, .offset = 3 },
    } });

    try std.testing.expectEqual(@as(u32, 0), @intFromEnum(storage.types.items[0].parameter));
    try std.testing.expect(storage.storageBytes() > 0);
}