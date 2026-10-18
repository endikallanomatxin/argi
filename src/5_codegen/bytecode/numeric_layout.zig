const std = @import("std");
const g = @import("../../4_semantics/global/graph.zig");
const types = @import("../../4_semantics/global/types.zig");
const b = @import("bytecode.zig");

/// Physical byte views support numeric data only. References and cleanup
/// evidence cannot be reconstructed from integer bytes. Descriptors belong to
/// the compilation arena and contain no semantic graph pointers.
pub const Layout = struct {
    size: usize,
    alignment: usize,
    shape: union(enum) {
        integer: struct { signed: bool },
        fields: []const Field,
        array: struct { element: *const Layout, length: usize, stride: usize },
    },

    pub const Field = struct { offset: usize, layout: *const Layout };
};

pub fn compile(allocator: std.mem.Allocator, graph: *const g.GlobalSemanticGraph, ty: g.GlobalTypeId) !*const Layout {
    return compileDepth(allocator, graph, ty, 0);
}

fn compileDepth(allocator: std.mem.Allocator, graph: *const g.GlobalSemanticGraph, ty: g.GlobalTypeId, depth: usize) anyerror!*const Layout {
    if (depth > 64) return error.UnsupportedNumericLayout;
    const physical = try types.layoutOf(graph, ty);
    const size = std.math.cast(usize, physical.size) orelse return error.Overflow;
    const alignment = std.math.cast(usize, physical.alignment) orelse return error.Overflow;
    const shape: @FieldType(Layout, "shape") = if (b.integerBounds(graph, ty)) |bounds| blk: {
        if (size == 0 or size > 8) return error.UnsupportedNumericLayout;
        break :blk .{ .integer = .{ .signed = bounds.minimum < 0 } };
    } else if (types.arrayElement(graph, ty)) |element_ty| blk: {
        const element = try compileDepth(allocator, graph, element_ty, depth + 1);
        const length = std.math.cast(usize, types.arrayLength(graph, ty).?) orelse return error.Overflow;
        const stride = try alignOffset(element.size, element.alignment);
        if (try std.math.mul(usize, stride, length) != size) return error.UnsupportedNumericLayout;
        break :blk .{ .array = .{ .element = element, .length = length, .stride = stride } };
    } else blk: {
        // Numeric unions and choices have overlapping or discriminated storage;
        // they need an explicit representation plan before byte access is valid.
        const semantic = graph.semanticType(ty);
        if (semantic == .declared and graph.declaration(semantic.declared).struct_layout == .c_union) return error.UnsupportedNumericLayout;
        if (semantic == .structural and semantic.structural.layout == .c_union) return error.UnsupportedNumericLayout;
        if (semantic == .generic) {
            const instance = types.genericInstance(graph, ty) orelse return error.UnsupportedNumericLayout;
            if (instance.shape == .structure and instance.shape.structure.layout == .c_union) return error.UnsupportedNumericLayout;
        }
        const fields = types.fields(graph, ty) orelse return error.UnsupportedNumericLayout;
        const result = try allocator.alloc(Layout.Field, fields.len);
        var offset: usize = 0;
        for (result, graph.fields.items[fields.start..][0..fields.len]) |*out, field| {
            const child = try compileDepth(allocator, graph, field.ty, depth + 1);
            offset = try alignOffset(offset, child.alignment);
            out.* = .{ .offset = offset, .layout = child };
            offset = try std.math.add(usize, offset, child.size);
        }
        if (try alignOffset(offset, alignment) != size) return error.UnsupportedNumericLayout;
        break :blk .{ .fields = result };
    };
    const result = try allocator.create(Layout);
    result.* = .{ .size = size, .alignment = alignment, .shape = shape };
    return result;
}

fn alignOffset(value: usize, alignment: usize) !usize {
    if (alignment == 0 or !std.math.isPowerOfTwo(alignment)) return error.UnsupportedNumericLayout;
    return (try std.math.add(usize, value, alignment - 1)) & ~(alignment - 1);
}

/// Read one representation byte without materializing a second backing buffer.
/// Padding has no semantic value; a deterministic zero never exposes host data.
pub fn readByte(layout: *const Layout, value: b.Value, offset: usize, endian: std.builtin.Endian) anyerror!u8 {
    if (offset >= layout.size) return error.ExecutionIndexOutOfBounds;
    return switch (layout.shape) {
        .integer => blk: {
            if (value != .integer) return error.ExecutionInvalidReference;
            const shift: u7 = @intCast(8 * (if (endian == .little) offset else layout.size - 1 - offset));
            break :blk @truncate(@as(u128, @bitCast(value.integer)) >> shift);
        },
        .fields => |fields| blk: {
            if (value != .record or value.record.len != fields.len) return error.ExecutionInvalidReference;
            for (fields, value.record) |field, child| {
                if (offset >= field.offset and offset - field.offset < field.layout.size)
                    break :blk try readByte(field.layout, child, offset - field.offset, endian);
            }
            break :blk 0;
        },
        .array => |array| blk: {
            if (value != .array or value.array.len != array.length or array.stride == 0) return error.ExecutionInvalidReference;
            const index = offset / array.stride;
            const within = offset % array.stride;
            if (within >= array.element.size) break :blk 0;
            break :blk try readByte(array.element, value.array[index], within, endian);
        },
    };
}

/// Produce an updated value without mutating shared aggregate slices. The
/// caller commits it through its evaluated storage destination afterwards.
pub fn writeByte(allocator: std.mem.Allocator, layout: *const Layout, value: b.Value, offset: usize, byte: u8, endian: std.builtin.Endian) anyerror!b.Value {
    if (offset >= layout.size) return error.ExecutionIndexOutOfBounds;
    return switch (layout.shape) {
        .integer => |integer| blk: {
            if (value != .integer) return error.ExecutionInvalidReference;
            const shift: u7 = @intCast(8 * (if (endian == .little) offset else layout.size - 1 - offset));
            const mask = @as(u128, 255) << shift;
            var bits = (@as(u128, @bitCast(value.integer)) & ~mask) | (@as(u128, byte) << shift);
            const width: u7 = @intCast(layout.size * 8);
            const limit = @as(u128, 1) << width;
            bits &= limit - 1;
            const number: i128 = @intCast(bits);
            break :blk .{ .integer = if (integer.signed and bits & (limit >> 1) != 0) number - @as(i128, @intCast(limit)) else number };
        },
        .fields => |fields| blk: {
            if (value != .record or value.record.len != fields.len) return error.ExecutionInvalidReference;
            for (fields, value.record, 0..) |field, child, index| {
                if (offset >= field.offset and offset - field.offset < field.layout.size) {
                    const updated = try writeByte(allocator, field.layout, child, offset - field.offset, byte, endian);
                    const copy = try allocator.dupe(b.Value, value.record);
                    copy[index] = updated;
                    break :blk .{ .record = copy };
                }
            }
            // Padding does not alter any language field.
            break :blk value;
        },
        .array => |array| blk: {
            if (value != .array or value.array.len != array.length or array.stride == 0) return error.ExecutionInvalidReference;
            const index = offset / array.stride;
            const within = offset % array.stride;
            if (within >= array.element.size) break :blk value;
            const updated = try writeByte(allocator, array.element, value.array[index], within, byte, endian);
            const copy = try allocator.dupe(b.Value, value.array);
            copy[index] = updated;
            break :blk .{ .array = copy };
        },
    };
}

test "numeric byte layouts retain target padding and reject references" {
    const a = std.testing.allocator;
    var graph: g.GlobalSemanticGraph = .{};
    defer graph.deinit(a);
    const source = @import("../../4_semantics/primitives/schema.zig").SourceRef{ .file_index = 0, .offset = 0 };
    try graph.types.appendSlice(a, &.{
        .{ .builtin = .UInt8 },
        .{ .builtin = .Int32 },
        .{ .structural = .{ .fields = .{ .start = 0, .len = 2 } } },
        .{ .pointer = .{ .child = @enumFromInt(0), .mutability = .read_only } },
        .{ .array = .{ .element = @enumFromInt(2), .length = 3 } },
    });
    for ([_][]const u8{ "tag", "number" }, 0..) |name, index|
        try graph.fields.append(a, .{ .name = try graph.addString(a, name), .source = source, .ty = @enumFromInt(@as(u32, @intCast(index))) });
    var arena = std.heap.ArenaAllocator.init(a);
    defer arena.deinit();
    const layout = try compile(arena.allocator(), &graph, @enumFromInt(2));
    try std.testing.expectEqual(@as(usize, 8), layout.size);
    try std.testing.expectEqual(@as(usize, 4), layout.alignment);
    try std.testing.expectEqual(@as(usize, 4), layout.shape.fields[1].offset);
    try std.testing.expect(layout.shape.fields[1].layout.shape.integer.signed);
    const array = try compile(arena.allocator(), &graph, @enumFromInt(4));
    try std.testing.expectEqual(@as(usize, 24), array.size);
    try std.testing.expectEqual(@as(usize, 8), array.shape.array.stride);
    try std.testing.expectError(error.UnsupportedNumericLayout, compile(arena.allocator(), &graph, @enumFromInt(3)));
}

test "numeric byte reads honor endianness signed values and padding" {
    const integer: Layout = .{ .size = 4, .alignment = 4, .shape = .{ .integer = .{ .signed = true } } };
    const byte: Layout = .{ .size = 1, .alignment = 1, .shape = .{ .integer = .{ .signed = false } } };
    const fields = [_]Layout.Field{ .{ .offset = 0, .layout = &byte }, .{ .offset = 4, .layout = &integer } };
    const record: Layout = .{ .size = 8, .alignment = 4, .shape = .{ .fields = &fields } };
    const values = [_]b.Value{ .{ .integer = 42 }, .{ .integer = -2 } };
    const value: b.Value = .{ .record = &values };
    try std.testing.expectEqual(@as(u8, 42), try readByte(&record, value, 0, .little));
    try std.testing.expectEqual(@as(u8, 0), try readByte(&record, value, 2, .little));
    try std.testing.expectEqual(@as(u8, 254), try readByte(&record, value, 4, .little));
    try std.testing.expectEqual(@as(u8, 255), try readByte(&record, value, 4, .big));
    try std.testing.expectEqual(@as(u8, 254), try readByte(&record, value, 7, .big));
    try std.testing.expectError(error.ExecutionIndexOutOfBounds, readByte(&record, value, 8, .little));
    try std.testing.expectError(error.ExecutionInvalidReference, readByte(&record, .unit, 0, .little));
}

test "numeric byte writes preserve siblings and interpret signed boundaries" {
    const number: Layout = .{ .size = 4, .alignment = 4, .shape = .{ .integer = .{ .signed = true } } };
    const fields = [_]Layout.Field{ .{ .offset = 0, .layout = &number }, .{ .offset = 4, .layout = &number } };
    const record: Layout = .{ .size = 8, .alignment = 4, .shape = .{ .fields = &fields } };
    const values = [_]b.Value{ .{ .integer = 0 }, .{ .integer = 42 } };
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const updated = try writeByte(arena.allocator(), &record, .{ .record = &values }, 3, 128, .little);
    try std.testing.expectEqual(@as(i128, -2147483648), updated.record[0].integer);
    try std.testing.expectEqual(@as(i128, 42), updated.record[1].integer);
    try std.testing.expectEqual(@as(i128, 0), values[0].integer);
    const big = try writeByte(arena.allocator(), &number, .{ .integer = 0 }, 0, 128, .big);
    try std.testing.expectEqual(@as(i128, -2147483648), big.integer);
}
