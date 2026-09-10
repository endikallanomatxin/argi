const std = @import("std");
const tok = @import("../../2_tokens/token.zig");
const syn = @import("../../3_syntax/syntax_tree.zig");
const primitives = @import("../primitives/schema.zig");

pub const ModuleDeclId = enum(u32) { _ };
pub const ModuleTypeId = enum(u32) { _ };
pub const ModuleFunctionId = enum(u32) { _ };
pub const ModuleBindingId = enum(u32) { _ };
pub const ModuleNodeId = enum(u32) { _ };
pub const ModuleBlockId = enum(u32) { _ };
pub const ModuleFieldId = enum(u32) { _ };
pub const ModuleVariantId = enum(u32) { _ };
pub const ModuleGenericArgId = enum(u32) { _ };
pub const ModuleValueFieldId = enum(u32) { _ };
pub const ModuleSwitchCaseId = enum(u32) { _ };
pub const ModuleSwitchId = enum(u32) { _ };
pub const ModuleAutoDeinitFieldId = enum(u32) { _ };
pub const ModuleAutoDeinitId = enum(u32) { _ };
pub const ModuleVirtualRegistryId = enum(u32) { _ };
pub const ModuleVirtualizeId = enum(u32) { _ };
pub const ModuleVirtualCallId = enum(u32) { _ };
pub const ModuleReachSegmentId = enum(u32) { _ };
pub const ModuleReachAlternativeId = enum(u32) { _ };
pub const ModuleReachId = enum(u32) { _ };
pub const ModuleNullableUnwrapId = enum(u32) { _ };
pub const ModuleTestingExpectErrorId = enum(u32) { _ };
pub const ModuleErrorPropagationId = enum(u32) { _ };
pub const ModuleErrorContextId = enum(u32) { _ };
pub const ModuleScopeId = enum(u32) { none = std.math.maxInt(u32), _ };
pub const ModuleFileId = enum(u32) { _ };
pub const ExternalRefId = enum(u32) { _ };
pub const PendingOperationId = enum(u32) { _ };

pub const Ids = struct {
    pub const DeclId = ModuleDeclId;
    pub const TypeId = ModuleTypeId;
    pub const FunctionId = ModuleFunctionId;
    pub const BindingId = ModuleBindingId;
    pub const NodeId = ModuleNodeId;
    pub const BlockId = ModuleBlockId;
    pub const FieldId = ModuleFieldId;
    pub const VariantId = ModuleVariantId;
    pub const GenericArgId = ModuleGenericArgId;
    pub const ValueFieldId = ModuleValueFieldId;
    pub const SwitchCaseId = ModuleSwitchCaseId;
    pub const SwitchId = ModuleSwitchId;
    pub const AutoDeinitFieldId = ModuleAutoDeinitFieldId;
    pub const AutoDeinitId = ModuleAutoDeinitId;
    pub const VirtualRegistryId = ModuleVirtualRegistryId;
    pub const VirtualizeId = ModuleVirtualizeId;
    pub const VirtualCallId = ModuleVirtualCallId;
    pub const ReachSegmentId = ModuleReachSegmentId;
    pub const ReachAlternativeId = ModuleReachAlternativeId;
    pub const ReachId = ModuleReachId;
    pub const NullableUnwrapId = ModuleNullableUnwrapId;
    pub const TestingExpectErrorId = ModuleTestingExpectErrorId;
    pub const ErrorPropagationId = ModuleErrorPropagationId;
    pub const ErrorContextId = ModuleErrorContextId;
};

pub const DeclRange = primitives.Range(ModuleDeclId);
pub const BindingRange = primitives.Range(ModuleBindingId);
pub const TypeRange = primitives.Range(ModuleTypeId);
pub const NodeRange = primitives.Range(ModuleNodeId);
pub const FieldRange = primitives.Range(ModuleFieldId);
pub const VariantRange = primitives.Range(ModuleVariantId);
pub const GenericArgRange = primitives.Range(ModuleGenericArgId);

pub const ResolvedType = primitives.SemanticType(Ids);
pub const Declaration = primitives.Declaration(Ids);
pub const Field = primitives.Field(Ids);
pub const ChoiceVariant = primitives.ChoiceVariant(Ids);
pub const GenericArgument = primitives.GenericArgument(Ids);
pub const Function = primitives.Function(Ids);
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

pub const ModuleType = union(enum) {
    resolved: ResolvedType,
    external: ExternalRefId,
};

pub const DeclarationSemantic = struct {
    declaration: ModuleDeclId,
    struct_layout: primitives.StructLayout = .regular,
    choice_layout: primitives.ChoiceLayout = .regular,
};

/// Cold relation for declaration kinds that own runtime storage. Keeping this
/// sparse avoids inflating every Declaration while making the identity explicit
/// for lookup, reach, Safety and Codegen.
pub const DeclarationBinding = struct {
    declaration: ModuleDeclId,
    binding: ModuleBindingId,
};

pub const FunctionSemantic = struct {
    function: ModuleFunctionId,
    body: ?ModuleBlockId = null,
    input_bindings: BindingRange = .{ .start = 0, .len = 0 },
    output_bindings: BindingRange = .{ .start = 0, .len = 0 },
    inferred_error_reasons: ?ModuleTypeId = null,
    safety_primitive: primitives.SafetyPrimitive = .none,
    flags: primitives.FunctionFlags = .{},
};

pub const FieldSemantic = struct {
    field: ModuleFieldId,
    storage_type: ?ModuleTypeId = null,
    default_value: ?ModuleNodeId = null,
};

pub const VariantSemantic = struct {
    variant: ModuleVariantId,
    value: i32,
    option_decl: ?ModuleDeclId = null,
};

pub const Scope = struct {
    parent: ModuleScopeId = .none,
    bindings: BindingRange = .{ .start = 0, .len = 0 },
};

pub const ExternalKind = enum(u8) {
    type,
    function,
    declaration,
    abstract,
    choice_option,
    module,
};

pub const ExternalRef = struct {
    kind: ExternalKind,
    module_path: ?primitives.StringRange,
    name: primitives.StringRange,
    generic_arguments: ?GenericArgRange = null,
    source: primitives.SourceRef,
};

/// Name lookups are the only expression-shaped operation still deferred as a
/// generic expression. All other globally-dependent constructs have dedicated
/// PendingOperation variants that encode their semantic intent explicitly.
pub const PendingExpressionKind = enum(u8) {
    unknown_identifier,
    import_value,
};

pub const PendingExpression = struct {
    node: ModuleNodeId,
    kind: PendingExpressionKind,
    operands: NodeRange = .{ .start = 0, .len = 0 },
    name: ?primitives.StringRange = null,
    expected_type: ?ModuleTypeId = null,
};

pub const PendingOperation = union(enum) {
    resolve_type: struct {
        external: ExternalRefId,
        destination: ModuleTypeId,
    },
    resolve_call: struct {
        node: ModuleNodeId,
        callee: ExternalRefId,
        input: ModuleNodeId,
        expected_type: ?ModuleTypeId = null,
    },
    resolve_field: struct {
        node: ModuleNodeId,
        value: ModuleNodeId,
        field_name: primitives.StringRange,
    },
    resolve_binary: struct {
        node: ModuleNodeId,
        operator: tok.BinaryOperator,
        left: ModuleNodeId,
        right: ModuleNodeId,
    },
    resolve_comparison: struct {
        node: ModuleNodeId,
        operator: tok.ComparisonOperator,
        left: ModuleNodeId,
        right: ModuleNodeId,
    },
    resolve_index: struct {
        node: ModuleNodeId,
        value: ModuleNodeId,
        index: ModuleNodeId,
        store_value: ?ModuleNodeId = null,
    },
    resolve_choice_literal: struct {
        node: ModuleNodeId,
        option: ExternalRefId,
        payload: ?ModuleNodeId,
        expected_type: ?ModuleTypeId = null,
    },
    resolve_choice_payload: struct {
        node: ModuleNodeId,
        value: ModuleNodeId,
        option_name: primitives.StringRange,
    },
    resolve_nullable_unwrap: struct {
        node: ModuleNodeId,
        nullable_value: ModuleNodeId,
        fallback_value: ModuleNodeId,
    },
    resolve_nullable_test: struct {
        node: ModuleNodeId,
        value: ModuleNodeId,
    },
    resolve_error_propagation: struct {
        node: ModuleNodeId,
        errable_value: ModuleNodeId,
        context: ?ModuleNodeId = null,
    },
    resolve_for_each: struct {
        node: ModuleNodeId,
        binding: ModuleBindingId,
        iterable: ModuleNodeId,
        body: ModuleBlockId,
        mode: syn.ForMode,
    },
    resolve_match: struct {
        node: ModuleNodeId,
        value: ModuleNodeId,
        cases: NodeRange,
    },
    resolve_match_case: struct {
        node: ModuleNodeId,
        option: ExternalRefId,
        payload_binding: ?ModuleBindingId,
        body: ModuleBlockId,
        mode: syn.MatchCaseMode,
    },
    resolve_defer: struct {
        node: ModuleNodeId,
        value: ModuleNodeId,
    },
    resolve_keep: struct {
        node: ModuleNodeId,
        binding: ModuleBindingId,
    },
    resolve_expression: PendingExpression,
    resolve_abstract: struct {
        declaration: ModuleDeclId,
        abstract_ref: ExternalRefId,
    },
    resolve_copy: struct {
        node: ModuleNodeId,
        value: ModuleNodeId,
    },
    resolve_deinit: struct {
        binding: ModuleBindingId,
    },
};

pub const ModuleNode = union(enum) {
    resolved: ResolvedNode,
    pending: PendingOperationId,
};

test "module semantic identities instantiate the shared schema" {
    const decl: ModuleDeclId = @enumFromInt(1);
    const resolved = ResolvedType{ .declared = decl };
    const ty = ModuleType{ .resolved = resolved };
    try std.testing.expectEqual(@as(u32, 1), @intFromEnum(ty.resolved.declared));

    const external = ExternalRef{
        .kind = .type,
        .module_path = null,
        .name = .{ .start = 0, .len = 5 },
        .generic_arguments = .{ .start = 2, .len = 1 },
        .source = .{ .file_index = 0, .offset = 7 },
    };
    try std.testing.expectEqual(ExternalKind.type, external.kind);
    try std.testing.expectEqual(@as(u32, 2), external.generic_arguments.?.start);

    const link = DeclarationBinding{ .declaration = decl, .binding = @enumFromInt(3) };
    try std.testing.expectEqual(@as(u32, 3), @intFromEnum(link.binding));

    const pending = PendingOperation{ .resolve_binary = .{
        .node = @enumFromInt(2),
        .operator = .addition,
        .left = @enumFromInt(0),
        .right = @enumFromInt(1),
    } };
    try std.testing.expectEqual(tok.BinaryOperator.addition, pending.resolve_binary.operator);
}
