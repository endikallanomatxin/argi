//! Read-only queries over selected evidence. These never perform dispatch or
//! infer participants; construction, cleanup and safety keep their own rules.
const graph_mod = @import("graph.zig");
const primitives = @import("../primitives/schema.zig");

/// Stable operation identity, independent of specialization and body aliases.
pub const Operation = struct {
    contract: graph_mod.GlobalFamilyDefinitionId,
    index: u32,
};

pub const SelectedOperation = struct {
    identity: Operation,
    conformance: graph_mod.ContractConformance,
    binding: graph_mod.ContractOperationBinding,

    pub fn definitionValue(self: SelectedOperation, graph: *const graph_mod.GlobalSemanticGraph) ?graph_mod.DefinitionValue {
        const definition = @import("types.zig").definitionValue(graph, self.binding.definition) orelse return null;
        return if (graph.familyDefinition(definition.origin).kind == .function) definition else null;
    }

    pub fn materializedFunction(self: SelectedOperation) ?graph_mod.GlobalFunctionId {
        return self.binding.materialized_function;
    }

    pub fn acceptsFunction(self: SelectedOperation, graph: *const graph_mod.GlobalSemanticGraph, function: graph_mod.GlobalFunctionId) bool {
        if (self.materializedFunction()) |selected| return selected == function;
        const definition = self.definitionValue(graph) orelse return false;
        const family = definition.origin;
        for (graph.generic_function_instances.items) |instance| {
            if (instance.function != function or instance.parameterized_definition != family) continue;
            const captures = if (self.binding.instantiate_associated) self.conformance.implementation_arguments else definition.captures;
            const associated = if (self.binding.instantiate_associated) self.conformance.associated_arguments else @as(primitives.Range(graph_mod.GlobalGenericArgId), .{ .start = 0, .len = 0 });
            if (instance.arguments.len < captures.len + associated.len) return false;
            for (0..captures.len + associated.len) |index| {
                const expected = if (index < captures.len)
                    graph.generic_arguments.items[captures.start + index]
                else
                    graph.generic_arguments.items[associated.start + index - captures.len];
                const actual = graph.generic_arguments.items[instance.arguments.start + index];
                if (!@import("types.zig").genericArgumentValuesEqual(graph, expected.value, actual.value)) return false;
            }
            return true;
        }
        return false;
    }

    pub fn participant(self: SelectedOperation, graph: *const graph_mod.GlobalSemanticGraph, index: usize) ?graph_mod.GlobalTypeId {
        if (index >= self.conformance.participants.len) return null;
        const argument = graph.generic_arguments.items[self.conformance.participants.start + index].value;
        return if (argument == .type) argument.type else null;
    }
};

pub fn selectedOperation(graph: *const graph_mod.GlobalSemanticGraph, selection: primitives.ContractOperationIdentity) ?SelectedOperation {
    if (selection.conformance >= graph.contract_conformances.items.len) return null;
    const conformance = graph.contract_conformances.items[selection.conformance];
    return operationInConformance(graph, conformance, selection.index);
}

pub fn operationInConformance(graph: *const graph_mod.GlobalSemanticGraph, conformance: graph_mod.ContractConformance, index: u32) ?SelectedOperation {
    if (index >= conformance.operation_bindings.len) return null;
    return .{
        .identity = .{ .contract = conformance.declaration, .index = index },
        .conformance = conformance,
        .binding = graph.contract_operation_bindings.items[conformance.operation_bindings.start + index],
    };
}

pub fn contractDefinition(graph: *const graph_mod.GlobalSemanticGraph, ty: graph_mod.GlobalTypeId) ?graph_mod.GlobalFamilyDefinitionId {
    const declaration = switch (graph.semanticType(ty)) {
        .definition => |declaration| declaration,
        .generic => |identity| identity.base,
        else => return null,
    };
    return if (graph.familyDefinition(declaration).kind == .contract) declaration else null;
}

pub fn virtualContractType(graph: *const graph_mod.GlobalSemanticGraph, call: graph_mod.VirtualCall) ?graph_mod.GlobalTypeId {
    const handle_type = graph.node(call.handle).ty orelse return null;
    const referent = switch (graph.semanticType(handle_type)) {
        .pointer => |pointer| pointer.child,
        else => handle_type,
    };
    const handle = graph.semanticType(referent);
    if (handle == .virtual) return handle.virtual;
    if (contractDefinition(graph, referent) != null) return referent;
    // The fixed erased signature remains authoritative if the handle's
    // expression has been adapted during call materialization.
    const fields = @import("types.zig").fields(graph, call.input_type) orelse return null;
    if (call.self_input_index >= fields.len) return null;
    const receiver = graph.fields.items[fields.start + call.self_input_index].ty;
    const child = switch (graph.semanticType(receiver)) {
        .pointer => |pointer| pointer.child,
        else => receiver,
    };
    return if (contractDefinition(graph, child) != null) child else null;
}

pub fn virtualOperation(graph: *const graph_mod.GlobalSemanticGraph, call: graph_mod.VirtualCall) ?Operation {
    const ty = virtualContractType(graph, call) orelse return null;
    const contract = contractDefinition(graph, ty) orelse return null;
    return .{ .contract = contract, .index = call.method_index };
}

pub fn associatedElement(graph: *const graph_mod.GlobalSemanticGraph, conformance: graph_mod.ContractConformance, index: usize) ?graph_mod.GenericArgument.Value {
    if (index >= conformance.associated_arguments.len) return null;
    return graph.generic_arguments.items[conformance.associated_arguments.start + index].value;
}

/// A borrowed view of materialized evidence; it owns no dispatch registry or
/// cache and therefore needs no independent invalidation or rollback.
pub const MaterializedOperations = struct {
    graph: *const graph_mod.GlobalSemanticGraph,
    contract: graph_mod.GlobalFamilyDefinitionId,
    conformance_index: usize = 0,
    operation_index: u32 = 0,

    pub fn next(self: *MaterializedOperations) ?SelectedOperation {
        while (self.conformance_index < self.graph.contract_conformances.items.len) {
            const conformance = self.graph.contract_conformances.items[self.conformance_index];
            if (conformance.declaration == self.contract) {
                while (self.operation_index < conformance.operation_bindings.len) {
                    const index = self.operation_index;
                    self.operation_index += 1;
                    if (operationInConformance(self.graph, conformance, index)) |selected|
                        if (selected.materializedFunction() != null) return selected;
                }
            }
            self.conformance_index += 1;
            self.operation_index = 0;
        }
        return null;
    }
};

pub fn materializedOperations(graph: *const graph_mod.GlobalSemanticGraph, contract: graph_mod.GlobalFamilyDefinitionId) MaterializedOperations {
    return .{ .graph = graph, .contract = contract };
}

pub fn operationForFunction(graph: *const graph_mod.GlobalSemanticGraph, contract: graph_mod.GlobalFamilyDefinitionId, function: graph_mod.GlobalFunctionId) ?SelectedOperation {
    for (graph.contract_conformances.items) |conformance| {
        if (conformance.declaration != contract) continue;
        for (0..conformance.operation_bindings.len) |index| {
            const selected = operationInConformance(graph, conformance, @intCast(index)) orelse continue;
            if (selected.acceptsFunction(graph, function)) return selected;
        }
    }
    return null;
}

/// Conservative call targets for once-use analysis, derived from materialized
/// handles rather than a mutable list stored in the erased signature. Multiple
/// handles can return the same method; consumers deduplicate by FunctionId.
pub const PossibleVirtualMethods = struct {
    graph: *const graph_mod.GlobalSemanticGraph,
    contract: graph_mod.GlobalTypeId,
    method_index: u32,
    cursor: usize = 0,

    pub fn next(self: *PossibleVirtualMethods) ?graph_mod.GlobalFunctionId {
        while (self.cursor < self.graph.virtualizes.items.len) {
            const candidate = self.graph.virtualizes.items[self.cursor];
            self.cursor += 1;
            if (self.method_index >= candidate.methods.len) continue;
            const ty = self.graph.resolvedSemanticType(candidate.virtual_type) orelse continue;
            if (ty != .virtual or !@import("types.zig").equal(self.graph, ty.virtual, self.contract)) continue;
            return self.graph.function_refs.items[candidate.methods.start + self.method_index];
        }
        return null;
    }
};

test "selected operation evidence checks bound definition captures" {
    const std = @import("std");
    const allocator = std.testing.allocator;
    var graph: graph_mod.GlobalSemanticGraph = .{};
    defer graph.deinit(allocator);
    const source: primitives.SourceRef = .{ .file_index = 0, .offset = 0 };
    try graph.family_definitions.append(allocator, .{ .kind = .function, .source = source, .parameter_count = 1 });
    const name = try graph.addString(allocator, "T");
    try graph.types.appendSlice(allocator, &.{ .{ .builtin = .Int32 }, .{ .builtin = .Bool } });
    try graph.generic_arguments.appendSlice(allocator, &.{
        .{ .name = name, .value = .{ .type = @enumFromInt(0) } },
        .{ .name = name, .value = .{ .type = @enumFromInt(1) } },
    });
    try graph.nodes.append(allocator, .{
        .source = source,
        .ty = null,
        .content = .{ .definition_literal = .{ .origin = @enumFromInt(0), .captures = .{ .start = 0, .len = 1 } } },
    });
    try graph.generic_function_instances.appendSlice(allocator, &.{
        .{ .function = @enumFromInt(0), .parameterized_definition = @enumFromInt(0), .arguments = .{ .start = 0, .len = 1 } },
        .{ .function = @enumFromInt(1), .parameterized_definition = @enumFromInt(0), .arguments = .{ .start = 1, .len = 1 } },
    });
    const evidence: SelectedOperation = .{
        .identity = .{ .contract = @enumFromInt(0), .index = 0 },
        .conformance = .{
            .declaration = @enumFromInt(0),
            .source = source,
            .participants = .{ .start = 0, .len = 0 },
            .associated_arguments = .{ .start = 0, .len = 0 },
        },
        .binding = .{
            .contract_definition = @enumFromInt(0),
            .requirement_index = 0,
            .requirement_source = source,
            .implementation_source = source,
            .name = name,
            .definition = @enumFromInt(0),
        },
    };
    try std.testing.expect(evidence.acceptsFunction(&graph, @enumFromInt(0)));
    try std.testing.expect(!evidence.acceptsFunction(&graph, @enumFromInt(1)));
}
