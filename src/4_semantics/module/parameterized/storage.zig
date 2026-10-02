const std = @import("std");
const entities = @import("../entities.zig");
const ir = @import("ir.zig");
const primitives = @import("../../primitives/schema.zig");
const callable = @import("../../primitives/callable.zig");

pub const ComptimeParameterId = ir.ComptimeParameterId;
pub const AbstractConstraintId = enum(u32) { _ };
pub const ParameterizedFunctionDefinitionId = enum(u32) { _ };
pub const ParameterizedTypeDefinitionId = enum(u32) { _ };
pub const AbstractRequirementId = enum(u32) { _ };
pub const AbstractDefinitionId = enum(u32) { _ };
pub const AbstractArgumentId = enum(u32) { _ };
pub const AbstractImplementationId = enum(u32) { _ };
pub const ParameterizedAbstractImplementationId = enum(u32) { _ };
pub const AbstractDefaultId = enum(u32) { _ };
pub const ParameterizedAbstractDefaultId = enum(u32) { _ };

pub const DeclarationRef = ir.DeclarationRef;

pub const ComptimeParameterKind = enum(u8) { type, comptime_int };
pub const GenericDispatchKind = enum(u8) { regular, abstract_contract };

pub const ComptimeParameter = struct {
    name: primitives.StringRange,
    kind: ComptimeParameterKind,
    value_type: ?ir.ParameterizedTypeId = null,
    constraint: ?AbstractConstraintId = null,
};

pub const AbstractConstraint = struct {
    abstract_ref: DeclarationRef,
    arguments: primitives.Range(ir.ParameterizedGenericArgId) = .{ .start = 0, .len = 0 },
    source: primitives.SourceRef,
};

pub const ParameterizedFunction = struct {
    declaration: entities.ModuleDeclId,
    parameters: primitives.Range(ComptimeParameterId),
    input: ir.ParameterizedTypeId,
    output: ir.ParameterizedTypeId,
    input_bindings: primitives.Range(ir.ParameterizedBindingId) = .{ .start = 0, .len = 0 },
    output_bindings: primitives.Range(ir.ParameterizedBindingId) = .{ .start = 0, .len = 0 },
    body: ?ir.ParameterizedBlockId,
    dispatch_kind: GenericDispatchKind = .regular,
    operator: ?callable.OperatorKind = null,
    /// Destructor identity is resolved once while FileST is available. Global
    /// ownership consumes this bit and never infers temporal semantics by name.
    is_deinit: bool = false,
    safety_primitive: primitives.SafetyPrimitive = .none,
};

pub const ParameterizedType = struct {
    declaration: entities.ModuleDeclId,
    parameters: primitives.Range(ComptimeParameterId),
    body: ir.ParameterizedTypeId,
};

pub const AbstractRequirement = struct {
    name: primitives.StringRange,
    input: ir.ParameterizedTypeId,
    output: ir.ParameterizedTypeId,
    parameters: primitives.Range(ComptimeParameterId) = .{ .start = 0, .len = 0 },
};

pub const AbstractDefinition = struct {
    declaration: entities.ModuleDeclId,
    parameters: primitives.Range(ComptimeParameterId),
    requirements: primitives.Range(AbstractRequirementId),
};

pub const AbstractArgument = union(enum) { none, type: entities.ModuleTypeId, comptime_int: i64 };

pub const AbstractImplementation = struct {
    abstract_ref: DeclarationRef,
    ty: entities.ModuleTypeId,
    arguments: primitives.Range(AbstractArgumentId) = .{ .start = 0, .len = 0 },
    source: primitives.SourceRef,
};

pub const ParameterizedAbstractImplementation = struct {
    abstract_ref: DeclarationRef,
    parameters: primitives.Range(ComptimeParameterId),
    concrete_type_pattern: ?ir.ParameterizedTypeId = null,
    concrete_name: ?primitives.StringRange = null,
    concrete_parameter_count: u32 = 0,
    arguments: primitives.Range(ir.ParameterizedGenericArgId) = .{ .start = 0, .len = 0 },
    source: primitives.SourceRef,
};

pub const AbstractDefault = struct {
    abstract_ref: DeclarationRef,
    ty: entities.ModuleTypeId,
    source: primitives.SourceRef,
};

pub const ParameterizedAbstractDefault = struct {
    abstract_ref: DeclarationRef,
    parameters: primitives.Range(ComptimeParameterId),
    ty: ir.ParameterizedTypeId,
    source: primitives.SourceRef,
};

pub const Storage = struct {
    ir: ir.Storage = .{},
    comptime_parameters: std.ArrayList(ComptimeParameter) = .empty,
    abstract_constraints: std.ArrayList(AbstractConstraint) = .empty,
    parameterized_functions: std.ArrayList(ParameterizedFunction) = .empty,
    parameterized_types: std.ArrayList(ParameterizedType) = .empty,
    abstract_requirements: std.ArrayList(AbstractRequirement) = .empty,
    abstract_definitions: std.ArrayList(AbstractDefinition) = .empty,
    abstract_arguments: std.ArrayList(AbstractArgument) = .empty,
    abstract_implementations: std.ArrayList(AbstractImplementation) = .empty,
    parameterized_abstract_implementations: std.ArrayList(ParameterizedAbstractImplementation) = .empty,
    abstract_defaults: std.ArrayList(AbstractDefault) = .empty,
    parameterized_abstract_defaults: std.ArrayList(ParameterizedAbstractDefault) = .empty,

    pub fn deinit(self: *Storage, allocator: std.mem.Allocator) void {
        self.ir.deinit(allocator);
        self.comptime_parameters.deinit(allocator);
        self.abstract_constraints.deinit(allocator);
        self.parameterized_functions.deinit(allocator);
        self.parameterized_types.deinit(allocator);
        self.abstract_requirements.deinit(allocator);
        self.abstract_definitions.deinit(allocator);
        self.abstract_arguments.deinit(allocator);
        self.abstract_implementations.deinit(allocator);
        self.parameterized_abstract_implementations.deinit(allocator);
        self.abstract_defaults.deinit(allocator);
        self.parameterized_abstract_defaults.deinit(allocator);
        self.* = .{};
    }

    pub fn storageBytes(self: *const Storage) usize {
        return self.ir.storageBytes() +
            self.comptime_parameters.items.len * @sizeOf(ComptimeParameter) +
            self.abstract_constraints.items.len * @sizeOf(AbstractConstraint) +
            self.parameterized_functions.items.len * @sizeOf(ParameterizedFunction) +
            self.parameterized_types.items.len * @sizeOf(ParameterizedType) +
            self.abstract_requirements.items.len * @sizeOf(AbstractRequirement) +
            self.abstract_definitions.items.len * @sizeOf(AbstractDefinition) +
            self.abstract_arguments.items.len * @sizeOf(AbstractArgument) +
            self.abstract_implementations.items.len * @sizeOf(AbstractImplementation) +
            self.parameterized_abstract_implementations.items.len * @sizeOf(ParameterizedAbstractImplementation) +
            self.abstract_defaults.items.len * @sizeOf(AbstractDefault) +
            self.parameterized_abstract_defaults.items.len * @sizeOf(ParameterizedAbstractDefault);
    }
};

test "module parameterized storage owns lowered parameterized IR" {
    const allocator = std.testing.allocator;
    var storage: Storage = .{};
    defer storage.deinit(allocator);
    try storage.comptime_parameters.append(allocator, .{ .name = .{ .start = 0, .len = 1 }, .kind = .type });
    try storage.ir.types.append(allocator, .{ .parameter = @enumFromInt(0) });
    try storage.parameterized_functions.append(allocator, .{
        .declaration = @enumFromInt(0),
        .parameters = .{ .start = 0, .len = 1 },
        .input = @enumFromInt(0),
        .output = @enumFromInt(0),
        .input_bindings = .{ .start = 0, .len = 1 },
        .output_bindings = .{ .start = 1, .len = 1 },
        .body = null,
        .operator = .add,
        .is_deinit = true,
    });
    try std.testing.expectEqual(@as(u32, 1), storage.parameterized_functions.items[0].input_bindings.len);
    try std.testing.expectEqual(callable.OperatorKind.add, storage.parameterized_functions.items[0].operator.?);
    try std.testing.expect(storage.parameterized_functions.items[0].is_deinit);
}
