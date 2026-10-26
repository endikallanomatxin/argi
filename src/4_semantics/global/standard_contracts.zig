const evidence = @import("contract_evidence.zig");
const std = @import("std");
const primitives = @import("../primitives/schema.zig");
const graph_mod = @import("graph.zig");

/// Standard contract identities belong to bundled core. A same-named user
/// contract cannot change construction, cleanup or conversion guarantees.
pub fn standardDefinition(graph: *const graph_mod.GlobalSemanticGraph, name: []const u8) ?graph_mod.GlobalFamilyDefinitionId {
    if (graph.indexedDeclarationsNamed(name)) |declarations| {
        for (declarations) |id| if (isBundledContract(graph, id)) return graph.familyForDeclaration(id);
        return null;
    }
    for (graph.declarations.items, 0..) |declaration, index| {
        if (declaration.kind != .contract_type or !std.mem.eql(u8, graph.text(declaration.name), name)) continue;
        const id: graph_mod.GlobalDeclId = @enumFromInt(@as(u32, @intCast(index)));
        if (isBundledContract(graph, id)) return graph.familyForDeclaration(id);
    }
    return null;
}

fn isBundledContract(graph: *const graph_mod.GlobalSemanticGraph, id: graph_mod.GlobalDeclId) bool {
    if (graph.declaration(id).kind != .contract_type) return false;
    const owner = graph.moduleForDeclaration(id) orelse return false;
    return graph.modules.items[@intFromEnum(owner)].is_bundled_core;
}

test "standard contract lookup preserves ownership with complete and stale indexes" {
    const allocator = std.testing.allocator;
    var graph: graph_mod.GlobalSemanticGraph = .{};
    defer graph.deinit(allocator);
    const name = try graph.addString(allocator, "Init");
    const source = primitives.SourceRef{ .file_index = 0, .offset = 0 };
    try graph.declarations.append(allocator, .{ .kind = .contract_type, .name = name, .source = source });
    try graph.declarations.append(allocator, .{ .kind = .contract_type, .name = name, .source = source });
    try graph.modules.append(allocator, .{ .dir = name, .files = .{ .start = 0, .len = 0 }, .declarations = .{ .start = 0, .len = 1 } });
    try graph.modules.append(allocator, .{ .dir = name, .files = .{ .start = 0, .len = 0 }, .declarations = .{ .start = 1, .len = 1 }, .is_bundled_core = true });
    for (0..2) |raw| {
        const definition: graph_mod.GlobalFamilyDefinitionId = @enumFromInt(@as(u32, @intCast(raw)));
        try graph.family_definitions.append(allocator, .{ .source = source, .kind = .contract, .parameter_count = 1, .declaration = @enumFromInt(@as(u32, @intCast(raw))) });
        graph.declarations.items[raw].family_definition = definition;
    }
    const expected: graph_mod.GlobalFamilyDefinitionId = @enumFromInt(1);
    try std.testing.expectEqual(expected, standardDefinition(&graph, "Init").?);
    _ = try graph.declarationsNamed(allocator, "Init");
    try std.testing.expectEqual(expected, standardDefinition(&graph, "Init").?);
    try std.testing.expect(standardDefinition(&graph, "Deinit") == null);
    const saved = graph.checkpoint();
    try graph.declarations.append(allocator, .{ .kind = .function, .name = name, .source = source });
    try std.testing.expect(graph.indexedDeclarationsNamed("Init") == null);
    try std.testing.expectEqual(expected, standardDefinition(&graph, "Init").?);
    _ = try graph.declarationsNamed(allocator, "Init");
    graph.rollback(allocator, saved);
    try std.testing.expectEqual(expected, standardDefinition(&graph, "Init").?);
}

pub fn initializedType(graph: *const graph_mod.GlobalSemanticGraph, function: graph_mod.GlobalFunctionId) ?graph_mod.GlobalTypeId {
    return participantOfOperation(graph, function, "Init");
}

pub fn deinitializedType(graph: *const graph_mod.GlobalSemanticGraph, function: graph_mod.GlobalFunctionId) ?graph_mod.GlobalTypeId {
    return participantOfOperation(graph, function, "Deinit");
}

fn participantOfOperation(graph: *const graph_mod.GlobalSemanticGraph, function: graph_mod.GlobalFunctionId, name: []const u8) ?graph_mod.GlobalTypeId {
    const declaration = standardDefinition(graph, name) orelse return null;
    const selected = evidence.operationForFunction(graph, declaration, function) orelse return null;
    return selected.participant(graph, 0);
}

pub const OperatorIdentity = struct { contract: []const u8, operation: []const u8 };

pub fn arithmeticOperation(operator: primitives.BinaryOperator) OperatorIdentity {
    return switch (operator) {
        .addition => .{ .contract = "Add", .operation = "add" },
        .subtraction => .{ .contract = "Subtract", .operation = "subtract" },
        .multiplication => .{ .contract = "Multiply", .operation = "multiply" },
        .division => .{ .contract = "Divide", .operation = "divide" },
        .modulo => .{ .contract = "Remainder", .operation = "remainder" },
    };
}

pub fn comparisonOperation(operator: primitives.ComparisonOperator) OperatorIdentity {
    return switch (operator) {
        .equal, .not_equal => .{ .contract = "Equal", .operation = "equal" },
        .less_than => .{ .contract = "CompareRelations", .operation = "less_than" },
        .less_than_or_equal => .{ .contract = "CompareRelations", .operation = "less_than_or_equal" },
        .greater_than => .{ .contract = "CompareRelations", .operation = "greater_than" },
        .greater_than_or_equal => .{ .contract = "CompareRelations", .operation = "greater_than_or_equal" },
    };
}

pub fn scalarComparisonPrimitive(name: []const u8) ?primitives.ComparisonOperator {
    const prefix = "__scalar_";
    if (!std.mem.startsWith(u8, name, prefix)) return null;
    for (std.meta.tags(primitives.ComparisonOperator)) |operator| {
        if (operator == .not_equal) continue;
        if (std.mem.eql(u8, name[prefix.len..], comparisonOperation(operator).operation)) return operator;
    }
    return null;
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
    inline for (.{ "Add", "Subtract", "Multiply", "Divide", "Remainder", "Equal", "CompareRelations" }) |name| {
        if (std.mem.eql(u8, contract, name)) return prefix ++ name ++ suffix;
    }
    return prefix ++ "operator" ++ suffix;
}
