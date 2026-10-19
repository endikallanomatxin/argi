const integer = @import("../5_codegen/integer_arithmetic.zig");
const p = @import("../4_semantics/primitives/schema.zig");
const std = @import("std");
const Storage = @import("storage.zig").Storage;
const Handle = @import("acquisitions.zig").Handle;
const Layout = @import("../5_codegen/bytecode/numeric_layout.zig").Layout;
const Value = @import("../5_codegen/bytecode/value.zig").Value;

// Typed numeric access uses compiler-selected physical layouts. Padding is not
// a value and need not be initialized. References/resources cannot be decoded
// from bytes; their eventual representation requires explicit evidence storage.
pub fn read(storage: *Storage, handle: Handle, offset: usize, layout: *const Layout, endian: std.builtin.Endian) anyerror!Value {
    _ = try storage.acquisitions.range(storage, handle, offset, layout.size, layout.alignment);
    return switch (layout.shape) {
        .integer => |kind| .{ .integer = integer.encode(try storage.acquisitions.loadInteger(storage, handle, offset, layout, endian), p.integerRangeForWidth(@intCast(layout.size * 8), kind.signed)) },
        .fields => |fields| blk: {
            const values = try storage.allocate(fields.len);
            for (fields, values) |field, *value| value.* = try read(storage, handle, offset + field.offset, field.layout, endian);
            break :blk .{ .record = values };
        },
        .array => |array| blk: {
            const values = try storage.allocate(array.length);
            for (values, 0..) |*value, index| value.* = try read(storage, handle, offset + index * array.stride, array.element, endian);
            break :blk .{ .array = values };
        },
    };
}

// Validate every leaf before the first mutation. Malformed values, bounds and
// range errors cannot publish an initialized prefix of an aggregate write.
pub fn write(storage: *Storage, handle: Handle, offset: usize, layout: *const Layout, value: Value, endian: std.builtin.Endian) !void {
    try walkWrite(storage, handle, offset, layout, value, endian, false);
    try walkWrite(storage, handle, offset, layout, value, endian, true);
}

fn walkWrite(storage: *Storage, handle: Handle, offset: usize, layout: *const Layout, value: Value, endian: std.builtin.Endian, commit: bool) anyerror!void {
    _ = try storage.acquisitions.range(storage, handle, offset, layout.size, layout.alignment);
    switch (layout.shape) {
        .integer => {
            if (value != .integer) return error.ExecutionInvalidReference;
            if (layout.size > 8) return error.ExecutionInvalidReference;
            const range = p.integerRangeForWidth(@intCast(layout.size * 8), layout.shape.integer.signed);
            if (value.integer > range.maximum - range.minimum) return error.ExecutionIntegerOutOfRange;
            var bytes: [8]u8 = undefined;
            try @import("../5_codegen/bytecode/numeric_layout.zig").encodeInteger(layout, integer.decode(value.integer, p.integerRangeForWidth(@intCast(layout.size * 8), layout.shape.integer.signed)), bytes[0..layout.size], endian);
            if (commit) try storage.acquisitions.write(storage, handle, offset, bytes[0..layout.size]);
        },
        .fields => |fields| {
            if (value != .record or value.record.len != fields.len) return error.ExecutionInvalidReference;
            for (fields, value.record) |field, child| try walkWrite(storage, handle, offset + field.offset, field.layout, child, endian, commit);
        },
        .array => |array| {
            if (value != .array or value.array.len != array.length) return error.ExecutionInvalidReference;
            for (value.array, 0..) |child, index| try walkWrite(storage, handle, offset + index * array.stride, array.element, child, endian, commit);
        },
    }
}
