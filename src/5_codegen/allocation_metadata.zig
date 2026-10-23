const std = @import("std");
const g = @import("../4_semantics/global/graph.zig");
const types = @import("../4_semantics/global/types.zig");
const cleanup = @import("cleanup_layout.zig");
const references = @import("reference_layout.zig");

pub const header_bytes: usize = 16;

// Compiler-owned geometry for a typed acquisition. Counts describe independent
// per-element ranges; bytes neither identify owners nor certify initialization.
pub const Shape = struct {
    cleanup_flags: u64,
    reference_leaves: u64,
    reference_bytes: u64,
    alignment: u64,
    header_bytes: u64,

    pub fn words(self: Shape) [5]u64 {
        return .{ self.cleanup_flags, self.reference_leaves, self.reference_bytes, self.alignment, self.header_bytes };
    }
};

pub fn describe(allocator: std.mem.Allocator, graph: *const g.GlobalSemanticGraph, ty: g.GlobalTypeId, owning: bool, counts: *cleanup.Counts, leaves: *references.Layout) !Shape {
    // Execution currently requires a native target. The private reference-view
    // ABI consists of four pointers and a 64-bit owner projection offset.
    if (graph.target.pointerBytes() != 8) return error.UnsupportedAllocationMetadataTarget;
    return .{
        .cleanup_flags = if (owning) try counts.count(allocator, graph, ty) else 0,
        .reference_leaves = try leaves.count(allocator, graph, ty),
        .reference_bytes = 40,
        .alignment = 8,
        .header_bytes = header_bytes,
    };
}

// A prepared executor reservation retains both byte representation and logical
// occupancy. These descriptors outlive execution and contain no graph pointers.
pub const Reservation = struct {
    endian: std.builtin.Endian,
    geometry: Shape,
    receipt: @import("bytecode/acquired_receipt.zig").Layout,
    physical: *const @import("bytecode/numeric_layout.zig").Layout,
    values: @import("bytecode/storage_layout.zig").Layout,
    cleanup: ?*const cleanup.Layout,
};

pub fn reservation(allocator: std.mem.Allocator, graph: *const g.GlobalSemanticGraph, ty: g.GlobalTypeId, receipt_type: g.GlobalTypeId, counts: *cleanup.Counts, owning: bool) !*const Reservation {
    const physical = try @import("bytecode/numeric_layout.zig").compileAcquired(allocator, graph, ty);
    const result = try allocator.create(Reservation);
    if (owning) _ = try counts.count(allocator, graph, ty);
    var leaves: references.Layout = .{};
    defer leaves.deinit(allocator);
    const geometry = try describe(allocator, graph, ty, owning, counts, &leaves);
    const receipt = try @import("bytecode/acquired_receipt.zig").compile(graph, receipt_type);
    if (receipt.metadata == null or receipt.grant == null) return error.InvalidAllocationMetadataPrimitive;
    result.* = .{
        .endian = graph.target.stdTarget().cpu.arch.endian(),
        .geometry = geometry,
        .receipt = receipt,
        .physical = physical,
        .values = try @import("bytecode/storage_layout.zig").compile(allocator, graph, ty),
        .cleanup = if (owning) counts.retained(ty) else null,
    };
    return result;
}

// A registered generic primitive selects its one type participant during
// ordinary specialization. No runtime type lookup or source-name dispatch.
pub fn participant(graph: *const g.GlobalSemanticGraph, function: g.GlobalFunctionId) !g.GlobalTypeId {
    for (graph.generic_function_instances.items) |instance| {
        if (instance.function != function) continue;
        if (instance.arguments.len != 1) return error.InvalidAllocationMetadataPrimitive;
        const argument = graph.generic_arguments.items[instance.arguments.start].value;
        if (argument != .type) return error.InvalidAllocationMetadataPrimitive;
        return argument.type;
    }
    return error.InvalidAllocationMetadataPrimitive;
}

pub fn outputFields(graph: *const g.GlobalSemanticGraph, function: g.Function) !g.FieldRange {
    if (function.input.len != 0 or function.output.len != 1) return error.InvalidAllocationMetadataPrimitive;
    const fields = types.fields(graph, graph.fields.items[function.output.start].ty) orelse return error.InvalidAllocationMetadataPrimitive;
    const names = [_][]const u8{ "cleanup_flags", "reference_leaves", "reference_bytes", "alignment", "header_bytes" };
    if (fields.len != names.len) return error.InvalidAllocationMetadataPrimitive;
    for (graph.fields.items[fields.start..][0..fields.len], names) |field, name| {
        if (!types.isBuiltin(graph, field.ty, .UIntNative) or !std.mem.eql(u8, graph.text(field.name), name)) return error.InvalidAllocationMetadataPrimitive;
    }
    return fields;
}

test "allocation metadata separates cleanup from reference storage geometry" {
    const a = std.testing.allocator;
    var graph: g.GlobalSemanticGraph = .{};
    defer graph.deinit(a);
    try graph.types.appendSlice(a, &.{
        .{ .builtin = .Int32 },
        .{ .pointer = .{ .child = @enumFromInt(0), .mutability = .read_write } },
        .{ .array = .{ .element = @enumFromInt(1), .length = 1000 } },
    });
    var counts: cleanup.Counts = .{};
    defer counts.deinit(a);
    var leaves: references.Layout = .{};
    defer leaves.deinit(a);
    const scalar = try describe(a, &graph, @enumFromInt(0), false, &counts, &leaves);
    try std.testing.expectEqual(@as(u64, 0), scalar.cleanup_flags);
    try std.testing.expectEqual(@as(u64, 0), scalar.reference_leaves);
    const owner = try describe(a, &graph, @enumFromInt(2), true, &counts, &leaves);
    try std.testing.expectEqual(@as(u64, 1001), owner.cleanup_flags);
    try std.testing.expectEqual(@as(u64, 1000), owner.reference_leaves);
    const borrowed = try describe(a, &graph, @enumFromInt(2), false, &counts, &leaves);
    try std.testing.expectEqual(@as(u64, 0), borrowed.cleanup_flags);
    try std.testing.expectEqual(owner.reference_leaves, borrowed.reference_leaves);
    try std.testing.expectEqual(@as(usize, 2), counts.values.count());
}
