const integer = @import("../5_codegen/integer_arithmetic.zig");
const p = @import("../4_semantics/primitives/schema.zig");
const std = @import("std");
const Storage = @import("storage.zig").Storage;
const Handle = @import("acquisitions.zig").Handle;
const Layout = @import("../5_codegen/bytecode/numeric_layout.zig").Layout;
const Value = @import("../5_codegen/bytecode/value.zig").Value;

// Typed numeric access uses compiler-selected physical layouts. Padding is not
// a value and need not be initialized. Bytes cannot reconstruct reference or
// cleanup evidence; prepared storage retains those obligations independently.
pub fn read(storage: *Storage, handle: Handle, offset: usize, layout: *const Layout, endian: std.builtin.Endian) anyerror!Value {
    var empty: []Value = &.{};
    switch (layout.shape) {
        .boolean, .integer, .floating => return readValidated(storage, handle, offset, layout, endian, &empty),
        .fields, .array => {},
    }
    const cells = try readableCells(storage, handle, offset, layout);
    if (cells > storage.limit -| storage.cells) return error.ExecutionMemoryLimit;
    // One backing allocation owns the entire numeric snapshot. Nested values
    // contain views into it, so allocation failure cannot leave partial trees.
    const backing = try storage.allocate(cells);
    errdefer {
        storage.allocator.free(backing);
        storage.cells -= cells;
    }
    var remaining = backing;
    const value = try readValidated(storage, handle, offset, layout, endian, &remaining);
    std.debug.assert(remaining.len == 0);
    return value;
}

// Inspect typed leaves only: record padding is neither a value nor required to
// be initialized. Failed reads publish no snapshots and consume no cell quota.
fn readableCells(storage: *Storage, handle: Handle, offset: usize, layout: *const Layout) anyerror!usize {
    _ = try storage.acquisitions.range(storage, handle, offset, layout.size, layout.alignment);
    return switch (layout.shape) {
        .boolean, .integer, .floating => blk: {
            try storage.acquisitions.requireInitialized(storage, handle, offset, layout.size);
            break :blk 0;
        },
        .fields => |fields| blk: {
            var count: usize = fields.len;
            for (fields) |field|
                count = std.math.add(usize, count, try readableCells(storage, handle, offset + field.offset, field.layout)) catch return error.ExecutionMemoryLimit;
            break :blk count;
        },
        .array => |array| blk: {
            var count: usize = array.length;
            for (0..array.length) |index|
                count = std.math.add(usize, count, try readableCells(storage, handle, offset + index * array.stride, array.element)) catch return error.ExecutionMemoryLimit;
            break :blk count;
        },
    };
}

fn readValidated(storage: *Storage, handle: Handle, offset: usize, layout: *const Layout, endian: std.builtin.Endian, remaining: *[]Value) anyerror!Value {
    _ = try storage.acquisitions.range(storage, handle, offset, layout.size, layout.alignment);
    return switch (layout.shape) {
        .boolean => blk: {
            var bytes: [1]u8 = undefined;
            try storage.acquisitions.read(storage, handle, offset, &bytes);
            break :blk .{ .boolean = bytes[0] & 1 != 0 };
        },
        .integer => |kind| .{ .integer = integer.encode(try storage.acquisitions.loadInteger(storage, handle, offset, layout, endian), p.integerRangeForWidth(@intCast(layout.size * 8), kind.signed)) },
        .floating => blk: {
            if (layout.size > 8) return error.ExecutionInvalidReference;
            var bytes: [8]u8 = undefined;
            try storage.acquisitions.read(storage, handle, offset, bytes[0..layout.size]);
            break :blk try @import("../5_codegen/bytecode/numeric_layout.zig").decodeFloat(layout, bytes[0..layout.size], endian);
        },
        .fields => |fields| blk: {
            const values = remaining.*[0..fields.len];
            remaining.* = remaining.*[fields.len..];
            for (fields, values) |field, *value| value.* = try readValidated(storage, handle, offset + field.offset, field.layout, endian, remaining);
            break :blk .{ .record = values };
        },
        .array => |array| blk: {
            const values = remaining.*[0..array.length];
            remaining.* = remaining.*[array.length..];
            for (values, 0..) |*value, index| value.* = try readValidated(storage, handle, offset + index * array.stride, array.element, endian, remaining);
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
        .boolean => {
            if (value != .boolean) return error.ExecutionInvalidReference;
            if (layout.size != 1) return error.ExecutionInvalidReference;
            if (commit) try storage.acquisitions.write(storage, handle, offset, &.{@intFromBool(value.boolean)});
        },
        .integer => {
            if (value != .integer) return error.ExecutionInvalidReference;
            if (layout.size > 8) return error.ExecutionInvalidReference;
            const range = p.integerRangeForWidth(@intCast(layout.size * 8), layout.shape.integer.signed);
            if (value.integer > range.maximum - range.minimum) return error.ExecutionIntegerOutOfRange;
            var bytes: [8]u8 = undefined;
            try @import("../5_codegen/bytecode/numeric_layout.zig").encodeInteger(layout, integer.decode(value.integer, p.integerRangeForWidth(@intCast(layout.size * 8), layout.shape.integer.signed)), bytes[0..layout.size], endian);
            if (commit) try storage.acquisitions.write(storage, handle, offset, bytes[0..layout.size]);
        },
        .floating => {
            if (layout.size > 8) return error.ExecutionInvalidReference;
            var bytes: [8]u8 = undefined;
            try @import("../5_codegen/bytecode/numeric_layout.zig").encodeFloat(layout, value, bytes[0..layout.size], endian);
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

fn failedAggregateSnapshot(allocator: std.mem.Allocator) !void {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var storage = try Storage.init(arena.allocator(), 1000);
    const region = try storage.acquisitions.acquire(&storage, 3, 1);
    try storage.acquisitions.write(&storage, region, 0, &.{ 10, 20, 30 });
    const byte: Layout = .{ .size = 1, .alignment = 1, .shape = .{ .integer = .{ .signed = false } } };
    const pair: Layout = .{ .size = 2, .alignment = 1, .shape = .{ .array = .{ .element = &byte, .length = 2, .stride = 1 } } };
    const record: Layout = .{ .size = 1, .alignment = 1, .shape = .{ .fields = &.{.{ .offset = 0, .layout = &byte }} } };
    const layout: Layout = .{ .size = 3, .alignment = 1, .shape = .{ .fields = &.{
        .{ .offset = 0, .layout = &pair },
        .{ .offset = 2, .layout = &record },
    } } };
    const before = storage.cells;
    storage.allocator = allocator;
    const value = read(&storage, region, 0, &layout, .little) catch |err| {
        try std.testing.expectEqual(before, storage.cells);
        var bytes: [3]u8 = undefined;
        try storage.acquisitions.read(&storage, region, 0, &bytes);
        try std.testing.expectEqualSlices(u8, &.{ 10, 20, 30 }, &bytes);
        return err;
    };
    // The two root fields, two array elements and one nested record field
    // occupy a single allocation, including their descriptor cells.
    const backing: []const Value = value.record.ptr[0..5];
    defer allocator.free(backing);
    try std.testing.expectEqual(before + 5, storage.cells);
    try std.testing.expectEqual(@as(u64, 10), value.record[0].array[0].integer);
    try std.testing.expectEqual(@as(u64, 20), value.record[0].array[1].integer);
    try std.testing.expectEqual(@as(u64, 30), value.record[1].record[0].integer);
}

test "acquired aggregate snapshots allocate one complete backing or preserve storage" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, failedAggregateSnapshot, .{});
}

test "acquired booleans share byte initialization and reject integer values before writing" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var storage = try Storage.init(arena.allocator(), 1024);
    const handle = try storage.acquisitions.acquire(&storage, 2, 1);
    const boolean: Layout = .{ .size = 1, .alignment = 1, .shape = .boolean };
    const pair: Layout = .{ .size = 2, .alignment = 1, .shape = .{ .array = .{ .element = &boolean, .length = 2, .stride = 1 } } };
    try std.testing.expectError(error.ExecutionUninitializedStorage, read(&storage, handle, 0, &boolean, .little));
    try std.testing.expectError(error.ExecutionInvalidReference, write(&storage, handle, 0, &pair, .{ .array = &.{ .{ .boolean = true }, .{ .integer = 1 } } }, .little));
    try std.testing.expectError(error.ExecutionUninitializedStorage, read(&storage, handle, 0, &boolean, .little));
    try storage.acquisitions.write(&storage, handle, 0, &.{1});
    try std.testing.expect((try read(&storage, handle, 0, &boolean, .little)).boolean);
    try write(&storage, handle, 0, &boolean, .{ .boolean = false }, .big);
    var bytes: [1]u8 = undefined;
    try storage.acquisitions.read(&storage, handle, 0, &bytes);
    try std.testing.expectEqual(@as(u8, 0), bytes[0]);
}
