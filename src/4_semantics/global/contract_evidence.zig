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

    pub fn materializedFunction(self: SelectedOperation) ?graph_mod.GlobalFunctionId {
        return self.binding.materialized_function;
    }

    pub fn acceptsFunction(self: SelectedOperation, graph: *const graph_mod.GlobalSemanticGraph, function: graph_mod.GlobalFunctionId) bool {
        if (self.materializedFunction()) |selected| return selected == function;
        if (self.binding.parameter_count == 0) return false;
        const family = graph.declaration(self.binding.declaration).family_definition orelse return false;
        for (graph.generic_function_instances.items) |instance|
            if (instance.function == function and instance.parameterized_definition == family) return true;
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
    var operations = materializedOperations(graph, contract);
    while (operations.next()) |selected| {
        if (selected.materializedFunction() == function) return selected;
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
