const std = @import("std");
const syn = @import("../../../3_syntax/syntax_tree.zig");
const entities = @import("../entities.zig");
const primitives = @import("../../primitives/schema.zig");

pub const ComptimeParameterId = enum(u32) { _ };
pub const ParameterizedIntExprId = enum(u32) { _ };
pub const ParameterizedTypeId = enum(u32) { _ };
pub const ParameterizedDeclId = enum(u32) { _ };
pub const ParameterizedFunctionId = enum(u32) { _ };
pub const ParameterizedBindingId = enum(u32) { _ };
pub const ParameterizedNodeId = enum(u32) { _ };
pub const ParameterizedBlockId = enum(u32) { _ };
pub const ParameterizedFieldId = enum(u32) { _ };
pub const ParameterizedVariantId = enum(u32) { _ };
pub const ParameterizedGenericArgId = enum(u32) { _ };
pub const ParameterizedValueFieldId = enum(u32) { _ };
pub const ParameterizedSwitchCaseId = enum(u32) { _ };
pub const ParameterizedSwitchId = enum(u32) { _ };
pub const ParameterizedAutoDeinitFieldId = enum(u32) { _ };
pub const ParameterizedAutoDeinitId = enum(u32) { _ };
pub const ParameterizedVirtualRegistryId = enum(u32) { _ };
pub const ParameterizedVirtualizeId = enum(u32) { _ };
pub const ParameterizedVirtualCallId = enum(u32) { _ };
pub const ParameterizedReachSegmentId = enum(u32) { _ };
pub const ParameterizedReachAlternativeId = enum(u32) { _ };
pub const ParameterizedReachId = enum(u32) { _ };
pub const ParameterizedNullableUnwrapId = enum(u32) { _ };
pub const ParameterizedTestingExpectErrorId = enum(u32) { _ };
pub const ParameterizedErrorPropagationId = enum(u32) { _ };
pub const ParameterizedErrorContextId = enum(u32) { _ };
pub const ParameterizedPendingId = enum(u32) { _ };
pub const ParameterizedMatchCaseId = enum(u32) { _ };

pub const Ids = struct {
    pub const DeclId = ParameterizedDeclId;
    pub const TypeId = ParameterizedTypeId;
    pub const FunctionId = ParameterizedFunctionId;
    pub const BindingId = ParameterizedBindingId;
    pub const NodeId = ParameterizedNodeId;
    pub const BlockId = ParameterizedBlockId;
    pub const FieldId = ParameterizedFieldId;
    pub const VariantId = ParameterizedVariantId;
    pub const GenericArgId = ParameterizedGenericArgId;
    pub const ValueFieldId = ParameterizedValueFieldId;
    pub const SwitchCaseId = ParameterizedSwitchCaseId;
    pub const SwitchId = ParameterizedSwitchId;
    pub const AutoDeinitFieldId = ParameterizedAutoDeinitFieldId;
    pub const AutoDeinitId = ParameterizedAutoDeinitId;
    pub const VirtualRegistryId = ParameterizedVirtualRegistryId;
    pub const VirtualizeId = ParameterizedVirtualizeId;
    pub const VirtualCallId = ParameterizedVirtualCallId;
    pub const ReachSegmentId = ParameterizedReachSegmentId;
    pub const ReachAlternativeId = ParameterizedReachAlternativeId;
    pub const ReachId = ParameterizedReachId;
    pub const NullableUnwrapId = ParameterizedNullableUnwrapId;
    pub const TestingExpectErrorId = ParameterizedTestingExpectErrorId;
    pub const ErrorPropagationId = ParameterizedErrorPropagationId;
    pub const ErrorContextId = ParameterizedErrorContextId;
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

pub const IntBinaryOperator = enum(u8) { add, subtract, multiply, divide, modulo };

pub const IntExpression = union(enum) {
    literal: i64,
    parameter: ComptimeParameterId,
    binary: struct {
        operator: IntBinaryOperator,
        left: ParameterizedIntExprId,
        right: ParameterizedIntExprId,
    },
};

pub const Type = union(enum) {
    concrete: entities.ModuleTypeId,
    parameter: ComptimeParameterId,
    abstract_self,
    external: entities.ExternalRefId,
    array: struct {
        length: ParameterizedIntExprId,
        element: ParameterizedTypeId,
    },
    resolved: primitives.SemanticType(Ids),
};

pub const Decl = struct { target: DeclarationRef };
pub const Function = struct { target: FunctionRef };
pub const Variant = union(enum) {
    reference: VariantRef,
    semantic: primitives.ChoiceVariant(Ids),
};

pub const GenericArgument = struct {
    name: primitives.StringRange,
    value: Value,

    pub const Value = union(enum) {
        type: ParameterizedTypeId,
        comptime_int: ParameterizedIntExprId,
    };
};

pub const ResolvedType = primitives.SemanticType(Ids);
pub const Field = primitives.Field(Ids);
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

pub const PendingExpressionKind = enum(u8) {
    unknown_identifier,
    pipe,
    unwrap_or,
    unwrap_or_do,
    nullable_test,
    generic_call,
    type_initializer,
    explicit_cast,
    choice_literal,
    field_access,
    choice_payload,
    error_propagation,
    error_context,
    index,
    index_store,
    binary,
    comparison,
    logical,
    if_statement,
    while_statement,
    for_each,
    match,
    match_case,
    defer_value,
    keep_binding,
    address_of,
    dereference,
    pointer_store,
    move_value,
    struct_value,
    list_value,
    return_statement,
    other,
};

pub const PendingExpression = struct {
    kind: PendingExpressionKind,
    operands: primitives.Range(ParameterizedNodeId) = .{ .start = 0, .len = 0 },
    name: ?primitives.StringRange = null,
    module_path: ?primitives.StringRange = null,
    generic_arguments: primitives.Range(ParameterizedGenericArgId) = .{ .start = 0, .len = 0 },
    expected_type: ?ParameterizedTypeId = null,
    match_cases: primitives.Range(ParameterizedMatchCaseId) = .{ .start = 0, .len = 0 },
    source: primitives.SourceRef,
    aux: u32 = 0,
};

pub const MatchCase = struct {
    name: primitives.StringRange,
    payload_binding: ?ParameterizedBindingId,
    body: ParameterizedBlockId,
    mode: syn.MatchCaseMode,
    source: primitives.SourceRef,
};

pub const Pending = union(enum) {
    resolve_name: struct {
        name: primitives.StringRange,
        source: primitives.SourceRef,
    },
    resolve_call: struct {
        name: primitives.StringRange,
        input: ParameterizedNodeId,
        source: primitives.SourceRef,
    },
    resolve_field: struct {
        value: ParameterizedNodeId,
        field_name: primitives.StringRange,
        source: primitives.SourceRef,
    },
    resolve_expression: PendingExpression,
    resolve_copy: struct { value: ParameterizedNodeId },
    resolve_deinit: struct { binding: ParameterizedBindingId },
};

pub const Node = union(enum) {
    resolved: ResolvedNode,
    pending: ParameterizedPendingId,
};

pub const Storage = struct {
    int_expressions: std.ArrayList(IntExpression) = .empty,
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
    match_cases: std.ArrayList(MatchCase) = .empty,

    node_refs: std.ArrayList(ParameterizedNodeId) = .empty,
    type_refs: std.ArrayList(ParameterizedTypeId) = .empty,
    binding_refs: std.ArrayList(ParameterizedBindingId) = .empty,
    function_refs: std.ArrayList(ParameterizedFunctionId) = .empty,
    virtual_registry_refs: std.ArrayList(ParameterizedVirtualRegistryId) = .empty,

    pub fn deinit(self: *Storage, allocator: std.mem.Allocator) void {
        inline for (.{
            &self.int_expressions, &self.types,              &self.declarations,          &self.functions,
            &self.variants,        &self.fields,             &self.generic_arguments,     &self.bindings,
            &self.nodes,           &self.blocks,             &self.value_fields,          &self.switch_cases,
            &self.switches,        &self.auto_deinit_fields, &self.auto_deinits,          &self.virtual_registries,
            &self.virtualizes,     &self.virtual_calls,      &self.reach_segments,        &self.reach_alternatives,
            &self.reaches,         &self.nullable_unwraps,   &self.testing_expect_errors, &self.error_propagations,
            &self.error_contexts,  &self.pending,            &self.match_cases,           &self.node_refs,
            &self.type_refs,       &self.binding_refs,       &self.function_refs,         &self.virtual_registry_refs,
        }) |list| list.deinit(allocator);
        self.* = .{};
    }

    pub fn storageBytes(self: *const Storage) usize {
        return self.int_expressions.items.len * @sizeOf(IntExpression) +
            self.types.items.len * @sizeOf(Type) +
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
            self.match_cases.items.len * @sizeOf(MatchCase) +
            self.node_refs.items.len * @sizeOf(ParameterizedNodeId) +
            self.type_refs.items.len * @sizeOf(ParameterizedTypeId) +
            self.binding_refs.items.len * @sizeOf(ParameterizedBindingId) +
            self.function_refs.items.len * @sizeOf(ParameterizedFunctionId) +
            self.virtual_registry_refs.items.len * @sizeOf(ParameterizedVirtualRegistryId);
    }
};

test "parameterized IR represents dependent type state without syntax refs" {
    const allocator = std.testing.allocator;
    var storage: Storage = .{};
    defer storage.deinit(allocator);

    try storage.types.append(allocator, .{ .parameter = @enumFromInt(0) });
    try storage.types.append(allocator, .abstract_self);
    try storage.int_expressions.append(allocator, .{ .parameter = @enumFromInt(0) });
    try storage.types.append(allocator, .{ .array = .{ .length = @enumFromInt(0), .element = @enumFromInt(0) } });
    try storage.variants.append(allocator, .{ .semantic = .{
        .name = .{ .start = 0, .len = 0 },
        .payload_type = @enumFromInt(0),
        .source = .{ .file_index = 0, .offset = 0 },
        .value = 0,
    } });
    try storage.nodes.append(allocator, .{ .pending = @enumFromInt(0) });
    try storage.pending.append(allocator, .{ .resolve_expression = .{
        .kind = .generic_call,
        .module_path = .{ .start = 0, .len = 0 },
        .generic_arguments = .{ .start = 0, .len = 1 },
        .source = .{ .file_index = 0, .offset = 3 },
    } });

    try std.testing.expectEqual(@as(u32, 0), @intFromEnum(storage.types.items[0].parameter));
    try std.testing.expectEqual(@as(u32, 0), @intFromEnum(storage.types.items[2].array.length));
    try std.testing.expectEqual(PendingExpressionKind.generic_call, storage.pending.items[0].resolve_expression.kind);
    try std.testing.expect(storage.storageBytes() > 0);
}
