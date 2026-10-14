//! Read-only queries over selected evidence. These never perform dispatch or
//! infer participants; construction, cleanup and safety keep their own rules.
const graph_mod = @import("graph.zig");
const primitives = @import("../primitives/schema.zig");

/// Stable operation identity, independent of specialization and body aliases.
pub const Operation = struct {
    contract: graph_mod.GlobalDeclId,
    index: u32,
};

pub const SelectedOperation = struct {
    identity: Operation,
    conformance: graph_mod.ContractConformance,
    binding: graph_mod.ContractOperationBinding,

    pub fn materializedFunction(self: SelectedOperation, graph: *const graph_mod.GlobalSemanticGraph) ?graph_mod.GlobalFunctionId {
        if (self.identity.index >= self.conformance.operations.len) return null;
        return graph.function_refs.items[self.conformance.operations.start + self.identity.index];
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

fn contractDeclaration(graph: *const graph_mod.GlobalSemanticGraph, ty: graph_mod.GlobalTypeId) ?graph_mod.GlobalDeclId {
    const declaration = switch (graph.semanticType(ty)) {
        .declared => |declaration| declaration,
        .generic => |identity| identity.base,
        else => return null,
    };
    return if (graph.declaration(declaration).kind == .contract_type) declaration else null;
}

pub fn virtualContractType(graph: *const graph_mod.GlobalSemanticGraph, call: graph_mod.VirtualCall) ?graph_mod.GlobalTypeId {
    const handle_type = graph.node(call.handle).ty orelse return null;
    const referent = switch (graph.semanticType(handle_type)) {
        .pointer => |pointer| pointer.child,
        else => handle_type,
    };
    const handle = graph.semanticType(referent);
    if (handle == .virtual) return handle.virtual;
    if (contractDeclaration(graph, referent) != null) return referent;
    // The fixed erased signature remains authoritative if the handle's
    // expression has been adapted during call materialization.
    const fields = @import("types.zig").fields(graph, call.input_type) orelse return null;
    if (call.self_input_index >= fields.len) return null;
    const receiver = graph.fields.items[fields.start + call.self_input_index].ty;
    const child = switch (graph.semanticType(receiver)) {
        .pointer => |pointer| pointer.child,
        else => receiver,
    };
    return if (contractDeclaration(graph, child) != null) child else null;
}

pub fn virtualOperation(graph: *const graph_mod.GlobalSemanticGraph, call: graph_mod.VirtualCall) ?Operation {
    const ty = virtualContractType(graph, call) orelse return null;
    const contract = contractDeclaration(graph, ty) orelse return null;
    return .{ .contract = contract, .index = call.method_index };
}

pub fn associatedElement(graph: *const graph_mod.GlobalSemanticGraph, conformance: graph_mod.ContractConformance, index: usize) ?graph_mod.GenericArgument.Value {
    if (index >= conformance.associated_arguments.len) return null;
    return graph.generic_arguments.items[conformance.associated_arguments.start + index].value;
}

pub fn operationForFunction(graph: *const graph_mod.GlobalSemanticGraph, contract: graph_mod.GlobalDeclId, function: graph_mod.GlobalFunctionId) ?SelectedOperation {
    for (graph.contract_conformances.items, 0..) |conformance, conformance_index| {
        if (conformance.declaration != contract) continue;
        for (graph.function_refs.items[conformance.operations.start..][0..conformance.operations.len], 0..) |operation, index| {
            if (operation == function) return selectedOperation(graph, .{ .conformance = @intCast(conformance_index), .index = @intCast(index) });
        }
    }
    return null;
}
