const std = @import("std");
const graph_mod = @import("../global/graph.zig");
const types = @import("../global/types.zig");
const c_abi = @import("../global/c_abi.zig");
const facts = @import("facts.zig");

/// Foreign addresses carry neither a validity root nor a storage acquisition
/// receipt. Preserve that distinction at field projections, using the same
/// tree for concrete checking and symbolic summaries. Numeric sibling fields
/// remain ordinary values. This describes outputs, not retention/free effects
/// of an external implementation, which remain binding obligations.
pub fn value(comptime Value: type, allocator: std.mem.Allocator, graph: *const graph_mod.GlobalSemanticGraph, ty: graph_mod.GlobalTypeId) !Value {
    return valueDepth(Value, allocator, graph, ty, 0);
}

fn valueDepth(comptime Value: type, allocator: std.mem.Allocator, graph: *const graph_mod.GlobalSemanticGraph, ty: graph_mod.GlobalTypeId, depth: usize) !Value {
    if (depth >= 32) return .{};
    if (graph.semanticType(ty) == .pointer or c_abi.isRawPointer(graph, ty)) return .{ .foreign_storage = true };
    const Field = if (Value == facts.ValueFacts) facts.FieldFacts else facts.OutputFieldEffect;
    if (types.arrayElement(graph, ty)) |element| {
        const child = try valueDepth(Value, allocator, graph, element, depth + 1);
        if (child.fields.len == 0) return child;
        const length = types.arrayLength(graph, ty) orelse return .{};
        const stored = try allocator.create(Value);
        stored.* = child;
        const fields = try allocator.alloc(Field, @intCast(length));
        // Elements share an immutable template; projections and writes build
        // their own facts. Uniform raw-address arrays need only a marker.
        for (fields, 0..) |*field, index| field.* = .{ .index = @intCast(index), .value = stored };
        return .{ .fields = fields };
    }
    const range = types.fields(graph, ty) orelse return .{};
    var fields: std.ArrayList(Field) = .empty;
    var has_foreign = false;
    const empty = struct {
        const value: Value = .{};
    };
    for (graph.fields.items[range.start..][0..range.len], 0..) |field, index| {
        const child = try valueDepth(Value, allocator, graph, types.effectiveFieldType(field), depth + 1);
        var stored: *const Value = &empty.value;
        if (child.foreign_storage or child.fields.len != 0) {
            has_foreign = true;
            const allocated = try allocator.create(Value);
            allocated.* = child;
            stored = allocated;
        }
        // Empty siblings prevent a numeric union member from inheriting the
        // foreign effects of another member through a missing-field fallback.
        try fields.append(allocator, .{ .index = @intCast(index), .value = stored });
    }
    if (!has_foreign) {
        fields.deinit(allocator);
        return .{};
    }
    return .{ .fields = try fields.toOwnedSlice(allocator) };
}

test "foreign record outputs preserve concrete and symbolic field provenance" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    var graph: graph_mod.GlobalSemanticGraph = .{};
    defer graph.deinit(allocator);
    try graph.types.appendSlice(allocator, &.{
        .{ .builtin = .Int32 },
        .{ .pointer = .{ .child = @enumFromInt(0), .mutability = .read_only } },
        .{ .structural = .{ .fields = .{ .start = 0, .len = 2 }, .layout = .c_struct } },
        .{ .structural = .{ .fields = .{ .start = 2, .len = 1 }, .layout = .c_struct } },
    });
    const field: graph_mod.Field = .{ .name = .{ .start = 0, .len = 0 }, .ty = @enumFromInt(0), .source = .{ .file_index = 0, .offset = 0 } };
    try graph.fields.append(allocator, field);
    var pointer = field;
    pointer.ty = @enumFromInt(1);
    try graph.fields.append(allocator, pointer);
    var nested = field;
    nested.ty = @enumFromInt(2);
    try graph.fields.append(allocator, nested);
    const concrete = try value(facts.ValueFacts, allocator, &graph, @enumFromInt(3));
    const symbolic = try value(facts.ValueEffect, allocator, &graph, @enumFromInt(3));
    try std.testing.expectEqual(@as(usize, 1), concrete.fields.len);
    try std.testing.expectEqual(concrete.fields[0].index, symbolic.fields[0].index);
    const leaf = concrete.fields[0].value.fields[1];
    const effect = symbolic.fields[0].value.fields[1];
    try std.testing.expectEqual(@as(u32, 1), leaf.index);
    try std.testing.expectEqual(leaf.index, effect.index);
    try std.testing.expect(leaf.value.foreign_storage and effect.value.foreign_storage);
    try std.testing.expectEqual(@as(usize, 0), leaf.value.dependencies.len);
    try std.testing.expectEqual(@as(usize, 0), leaf.value.storage_capabilities.len);
    try std.testing.expectEqual(@as(usize, 0), effect.value.fresh_storage_capabilities.len);
}

test "foreign arrays and unions retain leaf effects without acquiring storage" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    var graph: graph_mod.GlobalSemanticGraph = .{};
    defer graph.deinit(allocator);
    try graph.types.appendSlice(allocator, &.{
        .{ .builtin = .Int32 },
        .{ .pointer = .{ .child = @enumFromInt(0), .mutability = .read_only } },
        .{ .array = .{ .element = @enumFromInt(1), .length = 1000000 } },
        .{ .structural = .{ .fields = .{ .start = 0, .len = 2 }, .layout = .c_union } },
        .{ .array = .{ .element = @enumFromInt(3), .length = 2 } },
    });
    const field: graph_mod.Field = .{ .name = .{ .start = 0, .len = 0 }, .ty = @enumFromInt(0), .source = .{ .file_index = 0, .offset = 0 } };
    try graph.fields.append(allocator, field);
    var pointer = field;
    pointer.ty = @enumFromInt(1);
    try graph.fields.append(allocator, pointer);
    inline for (.{ facts.ValueFacts, facts.ValueEffect }) |Value| {
        const uniform = try value(Value, allocator, &graph, @enumFromInt(2));
        try std.testing.expect(uniform.foreign_storage);
        try std.testing.expectEqual(@as(usize, 0), uniform.fields.len);
        const alternatives = try value(Value, allocator, &graph, @enumFromInt(3));
        try std.testing.expectEqual(@as(usize, 2), alternatives.fields.len);
        try std.testing.expect(!alternatives.fields[0].value.foreign_storage);
        try std.testing.expectEqual(@as(usize, 0), alternatives.fields[0].value.fields.len);
        try std.testing.expect(alternatives.fields[1].value.foreign_storage);
        const array = try value(Value, allocator, &graph, @enumFromInt(4));
        try std.testing.expectEqual(@as(usize, 2), array.fields.len);
        try std.testing.expect(array.fields[0].value == array.fields[1].value);
        try std.testing.expect(array.fields[1].value.fields[1].value.foreign_storage);
        if (Value == facts.ValueFacts) {
            try std.testing.expectEqual(@as(usize, 0), array.fields[1].value.fields[1].value.storage_capabilities.len);
        } else {
            try std.testing.expectEqual(@as(usize, 0), array.fields[1].value.fields[1].value.fresh_storage_capabilities.len);
        }
    }
}
