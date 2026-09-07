const std = @import("std");
const syn = @import("../3_syntax/syntax_tree.zig");
const entities = @import("module_semantic_entities.zig");
const primitives = @import("semantic_primitives.zig");

pub const GenericParameterId = enum(u32) { _ };
pub const AbstractConstraintId = enum(u32) { _ };
pub const GenericFunctionTemplateId = enum(u32) { _ };
pub const GenericTypeTemplateId = enum(u32) { _ };
pub const AbstractRequirementId = enum(u32) { _ };
pub const AbstractDefinitionId = enum(u32) { _ };
pub const AbstractArgumentId = enum(u32) { _ };
pub const AbstractImplementationId = enum(u32) { _ };
pub const AbstractImplementationTemplateId = enum(u32) { _ };
pub const AbstractDefaultId = enum(u32) { _ };

pub const ModuleSyntaxRef = struct {
    file: entities.ModuleFileId,
    node: syn.NodeIndex,
};

pub const DeclarationRef = union(enum) {
    local: entities.ModuleDeclId,
    external: entities.ExternalRefId,
};

pub const GenericParameterKind = enum(u8) {
    type,
    comptime_int,
};

pub const GenericDispatchKind = enum(u8) {
    regular,
    abstract_contract,
};

pub const GenericParameter = struct {
    name: primitives.StringRange,
    kind: GenericParameterKind,
    value_type: ?entities.ModuleTypeId = null,
    constraint: ?AbstractConstraintId = null,
};

/// Constraint arguments remain a compact syntax pattern until the generic is
/// instantiated. The reference is persistent because its file identity is
/// module-local rather than an invocation SourceDb.FileId.
pub const AbstractConstraint = struct {
    abstract_ref: DeclarationRef,
    arguments: ?ModuleSyntaxRef = null,
    source: primitives.SourceRef,
};

pub const GenericFunctionTemplate = struct {
    declaration: entities.ModuleDeclId,
    parameters: primitives.Range(GenericParameterId),
    input: ModuleSyntaxRef,
    output: ModuleSyntaxRef,
    body: ?ModuleSyntaxRef,
    dispatch_kind: GenericDispatchKind = .regular,
};

pub const GenericTypeTemplate = struct {
    declaration: entities.ModuleDeclId,
    parameters: primitives.Range(GenericParameterId),
    body: ModuleSyntaxRef,
};

/// Abstract requirements intentionally retain their type-pattern syntax. This
/// preserves Self, nested generic patterns and associated constraints without
/// copying the pointer-heavy legacy AbstractFunctionReqSem representation.
pub const AbstractRequirement = struct {
    name: primitives.StringRange,
    input: ModuleSyntaxRef,
    output: ModuleSyntaxRef,
    parameters: primitives.Range(GenericParameterId) = .{ .start = 0, .len = 0 },
};

pub const AbstractDefinition = struct {
    declaration: entities.ModuleDeclId,
    parameters: primitives.Range(GenericParameterId),
    requirements: primitives.Range(AbstractRequirementId),
};

pub const AbstractArgument = union(enum) {
    none,
    type: entities.ModuleTypeId,
    comptime_int: i64,
};

pub const AbstractImplementation = struct {
    abstract_ref: DeclarationRef,
    ty: entities.ModuleTypeId,
    arguments: primitives.Range(AbstractArgumentId) = .{ .start = 0, .len = 0 },
    source: primitives.SourceRef,
};

pub const AbstractImplementationTemplate = struct {
    abstract_ref: DeclarationRef,
    parameters: primitives.Range(GenericParameterId),
    concrete_type_pattern: ?ModuleSyntaxRef = null,
    concrete_name: ?primitives.StringRange = null,
    concrete_parameter_count: u32 = 0,
    arguments: ?ModuleSyntaxRef = null,
    source: primitives.SourceRef,
};

pub const AbstractDefault = struct {
    abstract_ref: DeclarationRef,
    ty: entities.ModuleTypeId,
    source: primitives.SourceRef,
};

pub const Storage = struct {
    generic_parameters: std.ArrayList(GenericParameter) = .empty,
    abstract_constraints: std.ArrayList(AbstractConstraint) = .empty,
    generic_function_templates: std.ArrayList(GenericFunctionTemplate) = .empty,
    generic_type_templates: std.ArrayList(GenericTypeTemplate) = .empty,
    abstract_requirements: std.ArrayList(AbstractRequirement) = .empty,
    abstract_definitions: std.ArrayList(AbstractDefinition) = .empty,
    abstract_arguments: std.ArrayList(AbstractArgument) = .empty,
    abstract_implementations: std.ArrayList(AbstractImplementation) = .empty,
    abstract_implementation_templates: std.ArrayList(AbstractImplementationTemplate) = .empty,
    abstract_defaults: std.ArrayList(AbstractDefault) = .empty,

    pub fn deinit(self: *Storage, allocator: std.mem.Allocator) void {
        self.generic_parameters.deinit(allocator);
        self.abstract_constraints.deinit(allocator);
        self.generic_function_templates.deinit(allocator);
        self.generic_type_templates.deinit(allocator);
        self.abstract_requirements.deinit(allocator);
        self.abstract_definitions.deinit(allocator);
        self.abstract_arguments.deinit(allocator);
        self.abstract_implementations.deinit(allocator);
        self.abstract_implementation_templates.deinit(allocator);
        self.abstract_defaults.deinit(allocator);
        self.* = .{};
    }

    pub fn storageBytes(self: *const Storage) usize {
        return self.generic_parameters.items.len * @sizeOf(GenericParameter) +
            self.abstract_constraints.items.len * @sizeOf(AbstractConstraint) +
            self.generic_function_templates.items.len * @sizeOf(GenericFunctionTemplate) +
            self.generic_type_templates.items.len * @sizeOf(GenericTypeTemplate) +
            self.abstract_requirements.items.len * @sizeOf(AbstractRequirement) +
            self.abstract_definitions.items.len * @sizeOf(AbstractDefinition) +
            self.abstract_arguments.items.len * @sizeOf(AbstractArgument) +
            self.abstract_implementations.items.len * @sizeOf(AbstractImplementation) +
            self.abstract_implementation_templates.items.len * @sizeOf(AbstractImplementationTemplate) +
            self.abstract_defaults.items.len * @sizeOf(AbstractDefault);
    }
};

test "module template storage uses durable module syntax refs" {
    const allocator = std.testing.allocator;
    var storage: Storage = .{};
    defer storage.deinit(allocator);

    try storage.generic_parameters.append(allocator, .{
        .name = .{ .start = 0, .len = 1 },
        .kind = .type,
    });
    try storage.generic_function_templates.append(allocator, .{
        .declaration = @enumFromInt(0),
        .parameters = .{ .start = 0, .len = 1 },
        .input = .{ .file = @enumFromInt(0), .node = @enumFromInt(10) },
        .output = .{ .file = @enumFromInt(0), .node = @enumFromInt(11) },
        .body = .{ .file = @enumFromInt(0), .node = @enumFromInt(12) },
    });

    try std.testing.expectEqual(@as(usize, 1), storage.generic_function_templates.items.len);
    try std.testing.expect(storage.storageBytes() >= @sizeOf(GenericParameter));
}