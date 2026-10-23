const std = @import("std");
const g = @import("../../4_semantics/global/graph.zig");
const types = @import("../../4_semantics/global/types.zig");

// Prepared from the registered allocation-establishment input. Execution uses
// representation positions, never field names or semantic graph queries.
pub const Layout = struct {
    address: u32,
    size: u32,
    alignment: u32,
};

pub const Bounds = struct { address: usize, size: usize, alignment: usize };

pub fn decode(layout: Layout, value: @import("value.zig").Value) !Bounds {
    return .{
        .address = try word(value, layout.address),
        .size = try word(value, layout.size),
        .alignment = try word(value, layout.alignment),
    };
}

fn word(value: @import("value.zig").Value, index: u32) !usize {
    if (value != .record or index >= value.record.len or value.record[index] != .integer) return error.ExecutionInvalidAcquisition;
    return std.math.cast(usize, value.record[index].integer) orelse error.ExecutionInvalidAcquisition;
}

pub fn compile(graph: *const g.GlobalSemanticGraph, ty: g.GlobalTypeId) !Layout {
    const pointer = graph.semanticType(ty);
    if (pointer != .pointer) return error.InvalidAcquiredReceipt;
    const fields = types.fields(graph, pointer.pointer.child) orelse return error.InvalidAcquiredReceipt;
    var indices: [3]?u32 = .{ null, null, null };
    const names = [_][]const u8{ "_storage_address", "_storage_size", "_storage_alignment" };
    for (graph.fields.items[fields.start..][0..fields.len], 0..) |field, index| {
        for (names, 0..) |name, selected| if (std.mem.eql(u8, graph.text(field.name), name)) {
            if (indices[selected] != null or !types.isBuiltin(graph, field.ty, .UIntNative)) return error.InvalidAcquiredReceipt;
            indices[selected] = std.math.cast(u32, index) orelse return error.InvalidAcquiredReceipt;
        };
    }
    return .{
        .address = indices[0] orelse return error.InvalidAcquiredReceipt,
        .size = indices[1] orelse return error.InvalidAcquiredReceipt,
        .alignment = indices[2] orelse return error.InvalidAcquiredReceipt,
    };
}
