const std = @import("std");
const g = @import("../../4_semantics/global/graph.zig");
const types = @import("../../4_semantics/global/types.zig");

// Prepared from the registered allocation-establishment input. Execution uses
// representation positions, never field names or semantic graph queries.
pub const Layout = struct {
    address: u32,
    size: u32,
    alignment: u32,
    grant: ?struct { data: u32, address: u32, size: u32 } = null,
    metadata: ?struct { field: u32, extent: u32, some_ordinal: u32, value: u32, element_size: u32, count: u32 } = null,
};

pub const Bounds = struct {
    address: usize,
    size: usize,
    alignment: usize,
    grant: ?struct { address: usize, size: usize } = null,

    // Intersect the declared grant with authenticated backing without adding
    // addresses. Public fields can narrow selection, never enlarge acquisition.
    pub fn remaining(self: Bounds, address: usize) !usize {
        if (address < self.address or address - self.address > self.size) return error.ExecutionIndexOutOfBounds;
        var result = self.size - (address - self.address);
        if (self.grant) |grant| {
            if (address < grant.address or address - grant.address > grant.size) return error.ExecutionIndexOutOfBounds;
            result = @min(result, grant.size - (address - grant.address));
        }
        return result;
    }
};

pub fn decode(layout: Layout, value: @import("value.zig").Value) !Bounds {
    return .{
        .address = try word(value, layout.address),
        .size = try word(value, layout.size),
        .alignment = try word(value, layout.alignment),
        .grant = if (layout.grant) |grant| blk: {
            if (value != .record or grant.data >= value.record.len) return error.ExecutionInvalidAcquisition;
            break :blk .{
                .address = try word(value.record[grant.data], grant.address),
                .size = try word(value, grant.size),
            };
        } else null,
    };
}

pub const State = struct { token: usize, count: usize, element_size: usize };

pub fn decodeState(layout: Layout, value: @import("value.zig").Value) !?State {
    const metadata = layout.metadata orelse return null;
    const token = try word(value, metadata.field);
    if (value != .record or metadata.extent >= value.record.len) return error.ExecutionInvalidAcquisition;
    const extent = value.record[metadata.extent];
    if (extent != .choice) return error.ExecutionInvalidAcquisition;
    if (extent.choice.variant != metadata.some_ordinal) return .{ .token = token, .count = 0, .element_size = 0 };
    const payload = extent.choice.payload orelse return error.ExecutionInvalidAcquisition;
    if (payload.* != .record or metadata.value >= payload.record.len) return error.ExecutionInvalidAcquisition;
    return .{ .token = token, .count = try word(payload.record[metadata.value], metadata.count), .element_size = try word(payload.record[metadata.value], metadata.element_size) };
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
    var grant_data: ?u32 = null;
    var grant_size: ?u32 = null;
    var grant_address: ?u32 = null;
    for (graph.fields.items[fields.start..][0..fields.len], 0..) |field, index| {
        if (std.mem.eql(u8, graph.text(field.name), "size")) {
            if (!types.isBuiltin(graph, field.ty, .UIntNative)) return error.InvalidAcquiredReceipt;
            grant_size = @intCast(index);
        }
        if (std.mem.eql(u8, graph.text(field.name), "data")) {
            const data_fields = types.fields(graph, field.ty) orelse return error.InvalidAcquiredReceipt;
            for (graph.fields.items[data_fields.start..][0..data_fields.len], 0..) |data_field, data_index| {
                if (std.mem.eql(u8, graph.text(data_field.name), "address")) {
                    if (!types.isBuiltin(graph, data_field.ty, .UIntNative)) return error.InvalidAcquiredReceipt;
                    grant_address = @intCast(data_index);
                }
            }
            grant_data = @intCast(index);
        }
    }
    if ((grant_data != null or grant_size != null) and (grant_data == null or grant_size == null or grant_address == null)) return error.InvalidAcquiredReceipt;
    var metadata: @FieldType(Layout, "metadata") = null;
    var state_field: ?u32 = null;
    var extent_field: ?u32 = null;
    for (graph.fields.items[fields.start..][0..fields.len], 0..) |field, index| {
        if (std.mem.eql(u8, graph.text(field.name), "_slot_state")) {
            if (!types.isBuiltin(graph, field.ty, .UIntNative)) return error.InvalidAcquiredReceipt;
            state_field = @intCast(index);
        }
        if (std.mem.eql(u8, graph.text(field.name), "_slot_extent")) extent_field = @intCast(index);
    }
    if (state_field) |state| {
        const extent = extent_field orelse return error.InvalidAcquiredReceipt;
        const variants = types.variants(graph, graph.fields.items[fields.start + extent].ty) orelse return error.InvalidAcquiredReceipt;
        for (graph.variants.items[variants.start..][0..variants.len], 0..) |variant, ordinal| {
            const payload = variant.payload_type orelse continue;
            const members = types.fields(graph, payload) orelse return error.InvalidAcquiredReceipt;
            if (members.len != 1) return error.InvalidAcquiredReceipt;
            const shape = types.fields(graph, graph.fields.items[members.start].ty) orelse return error.InvalidAcquiredReceipt;
            var size_field: ?u32 = null;
            var count_field: ?u32 = null;
            for (graph.fields.items[shape.start..][0..shape.len], 0..) |member, index| {
                if (!types.isBuiltin(graph, member.ty, .UIntNative)) return error.InvalidAcquiredReceipt;
                if (std.mem.eql(u8, graph.text(member.name), "element_size")) size_field = @intCast(index);
                if (std.mem.eql(u8, graph.text(member.name), "count")) count_field = @intCast(index);
            }
            metadata = .{ .field = state, .extent = extent, .some_ordinal = @intCast(ordinal), .value = 0, .element_size = size_field orelse return error.InvalidAcquiredReceipt, .count = count_field orelse return error.InvalidAcquiredReceipt };
        }
        if (metadata == null) return error.InvalidAcquiredReceipt;
    }
    return .{
        .metadata = metadata,
        .grant = if (grant_data) |data| .{ .data = data, .address = grant_address.?, .size = grant_size.? } else null,
        .address = indices[0] orelse return error.InvalidAcquiredReceipt,
        .size = indices[1] orelse return error.InvalidAcquiredReceipt,
        .alignment = indices[2] orelse return error.InvalidAcquiredReceipt,
    };
}
