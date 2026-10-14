const std = @import("std");
const primitives = @import("../primitives/schema.zig");
const graph_mod = @import("graph.zig");

/// Standard contract identities belong to bundled core. A same-named user
/// contract cannot change construction, cleanup or conversion guarantees.
pub fn standardDeclaration(graph: *const graph_mod.GlobalSemanticGraph, name: []const u8) ?graph_mod.GlobalDeclId {
    for (graph.declarations.items, 0..) |declaration, index| {
        if (declaration.kind != .contract_type or !std.mem.eql(u8, graph.text(declaration.name), name)) continue;
        const id: graph_mod.GlobalDeclId = @enumFromInt(@as(u32, @intCast(index)));
        const owner = graph.moduleForDeclaration(id) orelse continue;
        if (graph.modules.items[@intFromEnum(owner)].is_bundled_core) return id;
    }
    return null;
}

pub fn initializedType(graph: *const graph_mod.GlobalSemanticGraph, function: graph_mod.GlobalFunctionId) ?graph_mod.GlobalTypeId {
    return participantOfOperation(graph, function, "Init");
}

pub fn deinitializedType(graph: *const graph_mod.GlobalSemanticGraph, function: graph_mod.GlobalFunctionId) ?graph_mod.GlobalTypeId {
    return participantOfOperation(graph, function, "Deinit");
}

fn participantOfOperation(graph: *const graph_mod.GlobalSemanticGraph, function: graph_mod.GlobalFunctionId, name: []const u8) ?graph_mod.GlobalTypeId {
    const declaration = standardDeclaration(graph, name) orelse return null;
    for (graph.contract_conformances.items) |conformance| {
        if (conformance.declaration != declaration or conformance.participants.len == 0) continue;
        for (graph.function_refs.items[conformance.operations.start..][0..conformance.operations.len]) |operation| {
            if (operation != function) continue;
            return graph.generic_arguments.items[conformance.participants.start].value.type;
        }
    }
    return null;
}

pub const ArithmeticOperation = struct { contract: []const u8, operation: []const u8 };

pub fn arithmeticOperation(operator: primitives.BinaryOperator) ArithmeticOperation {
    return switch (operator) {
        .addition => .{ .contract = "Add", .operation = "add" },
        .subtraction => .{ .contract = "Subtract", .operation = "subtract" },
        .multiplication => .{ .contract = "Multiply", .operation = "multiply" },
        .division => .{ .contract = "Divide", .operation = "divide" },
        .modulo => .{ .contract = "Remainder", .operation = "remainder" },
    };
}

pub fn scalarArithmeticPrimitive(name: []const u8) ?primitives.BinaryOperator {
    const prefix = "__scalar_";
    if (!std.mem.startsWith(u8, name, prefix)) return null;
    for (std.meta.tags(primitives.BinaryOperator)) |operator| {
        if (std.mem.eql(u8, name[prefix.len..], arithmeticOperation(operator).operation)) return operator;
    }
    return null;
}

/// Diagnostics retain the selected identity without allocating messages into
/// graph storage that a failed speculative operation will roll back.
pub fn operatorMessage(contract: []const u8, comptime prefix: []const u8, comptime suffix: []const u8) []const u8 {
    inline for (.{ "Add", "Subtract", "Multiply", "Divide", "Remainder", "Equal" }) |name| {
        if (std.mem.eql(u8, contract, name)) return prefix ++ name ++ suffix;
    }
    return prefix ++ "operator" ++ suffix;
}
