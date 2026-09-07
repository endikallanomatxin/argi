const std = @import("std");
const primitives = @import("semantic_primitives.zig");

pub const ModuleDeclId = enum(u32) { _ };
pub const ModuleTypeId = enum(u32) { _ };
pub const ModuleFunctionId = enum(u32) { _ };
pub const ModuleBindingId = enum(u32) { _ };
pub const ModuleNodeId = enum(u32) { _ };
pub const ModuleBlockId = enum(u32) { _ };
pub const ModuleFieldId = enum(u32) { _ };
pub const ModuleVariantId = enum(u32) { _ };
pub const ModuleGenericArgId = enum(u32) { _ };
pub const ModuleScopeId = enum(u32) { none = std.math.maxInt(u32), _ };
pub const ModuleFileId = enum(u32) { _ };
pub const ExternalRefId = enum(u32) { _ };
pub const PendingOperationId = enum(u32) { _ };

pub const DeclRange = primitives.Range(ModuleDeclId);
pub const BindingRange = primitives.Range(ModuleBindingId);
pub const NodeRange = primitives.Range(ModuleNodeId);
pub const FieldRange = primitives.Range(ModuleFieldId);
pub const VariantRange = primitives.Range(ModuleVariantId);
pub const GenericArgRange = primitives.Range(ModuleGenericArgId);

pub const ModuleType = primitives.SemanticType(ModuleTypeId, ModuleDeclId, ModuleFieldId, ModuleGenericArgId);
pub const Field = primitives.Field(ModuleTypeId, ModuleNodeId);
pub const ChoiceVariant = primitives.ChoiceVariant(ModuleTypeId, ModuleDeclId);
pub const GenericTypeArgument = primitives.GenericTypeArgument(ModuleTypeId);
pub const Function = primitives.Function(ModuleDeclId, ModuleFieldId, ModuleBlockId, ModuleBindingId, ModuleTypeId);
pub const Binding = primitives.Binding(ModuleTypeId, ModuleNodeId);
pub const Block = primitives.Block(ModuleNodeId);
pub const ResolvedNode = primitives.Node(ModuleNodeId, ModuleTypeId, ModuleDeclId, ModuleFunctionId, ModuleBindingId, ModuleBlockId, ModuleFieldId, ModuleVariantId);

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

/// Symbolic reference whose answer is intentionally not fixed by ModuleSema.
/// `module_path` is absent for an unqualified open-world lookup and present for
/// an explicitly imported/qualified module reference.
pub const ExternalRef = struct {
    kind: ExternalKind,
    module_path: ?primitives.StringRange,
    name: primitives.StringRange,
    source: primitives.SourceRef,
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
    },
    resolve_field: struct {
        node: ModuleNodeId,
        value: ModuleNodeId,
        field_name: primitives.StringRange,
    },
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

/// Module nodes either contain a semantic fact whose identity is completely
/// module-local, or a typed hole that globalization must resolve. The resolved
/// payload uses exactly the same schema as GlobalSemanticGraph nodes.
pub const ModuleNode = union(enum) {
    resolved: ResolvedNode,
    pending: PendingOperationId,
};

test "module semantic identities stay separate" {
    const decl: ModuleDeclId = @enumFromInt(1);
    const ty = ModuleType{ .declared = decl };
    try std.testing.expectEqual(@as(u32, 1), @intFromEnum(ty.declared));

    const external = ExternalRef{
        .kind = .type,
        .module_path = null,
        .name = .{ .start = 0, .len = 5 },
        .source = .{ .file_index = 0, .offset = 7 },
    };
    try std.testing.expectEqual(ExternalKind.type, external.kind);
}
