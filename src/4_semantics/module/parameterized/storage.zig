const std = @import("std");
const entities = @import("../entities.zig");
const ir = @import("ir.zig");
const primitives = @import("../../primitives/schema.zig");

pub const ComptimeParameterId = ir.ComptimeParameterId;
pub const ContractConstraintId = enum(u32) { _ };
pub const ParameterizedFunctionDefinitionId = enum(u32) { _ };
pub const ParameterizedTypeDefinitionId = enum(u32) { _ };
pub const ContractRequirementId = enum(u32) { _ };
pub const ContractDefinitionId = enum(u32) { _ };

pub const DeclarationRef = ir.DeclarationRef;

pub const ComptimeParameterKind = enum(u8) { type, comptime_int };

pub const ComptimeParameter = struct {
    name: primitives.StringRange,
    kind: ComptimeParameterKind,
    value_type: ?ir.ParameterizedTypeId = null,
    default_type: ?ir.ParameterizedTypeId = null,
    default_integer: ?ir.ParameterizedIntExprId = null,
    constraint: ?ContractConstraintId = null,
};

pub const ContractConstraint = struct {
    contract_ref: DeclarationRef,
    arguments: primitives.Range(ir.ParameterizedGenericArgId) = .{ .start = 0, .len = 0 },
    source: primitives.SourceRef,
};

pub const ParameterizedFunction = struct {
    // A concrete identity may retain its body here when conditional compilation
    // needs staged materialization; it is never a generic dispatch candidate.
    is_comptime_entry: bool = false,
    is_comptime_host_entry: bool = false,
    concrete_function: ?entities.ModuleFunctionId = null,
    declaration: entities.ModuleDeclId,
    parameters: primitives.Range(ComptimeParameterId),
    input: ir.ParameterizedTypeId,
    output: ir.ParameterizedTypeId,
    input_bindings: primitives.Range(ir.ParameterizedBindingId) = .{ .start = 0, .len = 0 },
    output_bindings: primitives.Range(ir.ParameterizedBindingId) = .{ .start = 0, .len = 0 },
    body: ?ir.ParameterizedBlockId,
    /// Destructor identity is resolved once while FileST is available. Global
    /// ownership consumes this bit and never infers temporal semantics by name.
    safety_primitive: primitives.SafetyPrimitive = .none,
};

pub const ParameterizedType = struct {
    declaration: entities.ModuleDeclId,
    parameters: primitives.Range(ComptimeParameterId),
    body: ir.ParameterizedTypeId,
};

pub const ContractRequirement = struct {
    parameters: primitives.Range(ComptimeParameterId) = .{ .start = 0, .len = 0 },
    source: primitives.SourceRef = .{ .file_index = 0, .offset = 0 },
    name: primitives.StringRange,
    input: ir.ParameterizedTypeId,
    output: ir.ParameterizedTypeId,
    safety_contract: ?primitives.MethodSafetyContract = null,
};

pub const ContractDefinition = struct {
    participants: primitives.Range(ComptimeParameterId) = .{ .start = 0, .len = 0 },
    // Dependencies retain their own operation namespaces and are proved against
    // the selected participant/associated bindings.
    composition: primitives.Range(ContractConstraintId) = .{ .start = 0, .len = 0 },
    declaration: entities.ModuleDeclId,
    parameters: primitives.Range(ComptimeParameterId),
    requirements: primitives.Range(ContractRequirementId),
    domains: []const primitives.StringRange = &.{},

    pub fn hasExplicitParticipants(self: ContractDefinition) bool {
        return self.participants.len != 0;
    }
};

pub const DomainMapping = struct {
    name: primitives.StringRange,
    paths: []const Path,
    pub const Path = struct { fields: []const primitives.StringRange };

    pub fn deinit(self: DomainMapping, allocator: std.mem.Allocator) void {
        for (self.paths) |path| allocator.free(path.fields);
        allocator.free(self.paths);
    }
};

// Tuple evidence keeps selector arguments separate from associated outputs.
pub const ContractOperationId = enum(u32) { _ };
pub const ContractOperation = struct {
    instantiate_associated: bool = false,
    name: primitives.StringRange,
    function: DeclarationRef,
    source: primitives.SourceRef,
};
pub const ContractConformance = struct {
    parameters: primitives.Range(ComptimeParameterId) = .{ .start = 0, .len = 0 },
    operations: primitives.Range(ContractOperationId) = .{ .start = 0, .len = 0 },
    contract_ref: DeclarationRef,
    participants: primitives.Range(ir.ParameterizedGenericArgId),
    associated_arguments: primitives.Range(ir.ParameterizedGenericArgId),
    source: primitives.SourceRef,
    domains: []const DomainMapping = &.{},
};

pub const Storage = struct {
    ir: ir.Storage = .{},
    comptime_parameters: std.ArrayList(ComptimeParameter) = .empty,
    contract_constraints: std.ArrayList(ContractConstraint) = .empty,
    parameterized_functions: std.ArrayList(ParameterizedFunction) = .empty,
    parameterized_types: std.ArrayList(ParameterizedType) = .empty,
    contract_requirements: std.ArrayList(ContractRequirement) = .empty,
    contract_definitions: std.ArrayList(ContractDefinition) = .empty,
    // Names share the argument index; empty names denote positional arguments.
    contract_conformances: std.ArrayList(ContractConformance) = .empty,
    contract_operations: std.ArrayList(ContractOperation) = .empty,

    pub fn deinit(self: *Storage, allocator: std.mem.Allocator) void {
        self.ir.deinit(allocator);
        self.comptime_parameters.deinit(allocator);
        self.contract_constraints.deinit(allocator);
        self.parameterized_functions.deinit(allocator);
        self.parameterized_types.deinit(allocator);
        self.contract_requirements.deinit(allocator);
        for (self.contract_definitions.items) |definition| allocator.free(definition.domains);
        self.contract_definitions.deinit(allocator);
        for (self.contract_conformances.items) |conformance| {
            for (conformance.domains) |domain| domain.deinit(allocator);
            allocator.free(conformance.domains);
        }
        self.contract_conformances.deinit(allocator);
        self.contract_operations.deinit(allocator);
        self.* = .{};
    }

    pub fn storageBytes(self: *const Storage) usize {
        return self.ir.storageBytes() +
            self.comptime_parameters.items.len * @sizeOf(ComptimeParameter) +
            self.contract_constraints.items.len * @sizeOf(ContractConstraint) +
            self.parameterized_functions.items.len * @sizeOf(ParameterizedFunction) +
            self.parameterized_types.items.len * @sizeOf(ParameterizedType) +
            self.contract_requirements.items.len * @sizeOf(ContractRequirement) +
            self.contract_definitions.items.len * @sizeOf(ContractDefinition) +
            self.contract_conformances.items.len * @sizeOf(ContractConformance) +
            self.contract_operations.items.len * @sizeOf(ContractOperation);
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
    });
    try std.testing.expectEqual(@as(u32, 1), storage.parameterized_functions.items[0].input_bindings.len);
}
