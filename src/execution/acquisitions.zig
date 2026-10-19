const std = @import("std");
const storage_mod = @import("storage.zig");
const v = @import("../5_codegen/bytecode/value.zig");

pub const RegionId = enum(u32) { _ };
pub const Handle = struct { context: v.ContextId, region: RegionId };
pub const Range = struct { handle: Handle, offset: usize, length: usize };
const Region = struct { length: usize, alignment: usize, bytes: []u8, initialized: []u8, live: bool = true };

/// Concrete acquisition identities, separate from lexical slots and host
/// addresses. A receipt proves a live byte extent, never initialized typed data
/// or a language borrow. Released entries remain tombstones until context reset.
/// The execution arena owns the table and byte backing. Initialization bits
/// describe concrete bytes only, without reproducing static lifetime proofs.
pub const Regions = struct {
    entries: std.ArrayList(Region) = .empty,

    pub fn acquire(self: *Regions, storage: *storage_mod.Storage, length: usize, alignment: usize) !Handle {
        if (alignment == 0 or !std.math.isPowerOfTwo(alignment)) return error.ExecutionInvalidAlignment;
        const id: RegionId = @enumFromInt(std.math.cast(u32, self.entries.items.len) orelse return error.ExecutionAcquisitionLimit);
        const bitmap_length = length / 8 + @intFromBool(length % 8 != 0);
        const charge = std.math.add(usize, std.math.add(usize, length, bitmap_length) catch return error.ExecutionMemoryLimit, 1) catch return error.ExecutionMemoryLimit;
        // Check the quota before allocating large backing, then reserve every
        // allocation before charging or publishing the complete acquisition.
        if (charge > storage.limit -| storage.cells) return error.ExecutionMemoryLimit;
        try self.entries.ensureUnusedCapacity(storage.allocator, 1);
        const bytes = try storage.allocator.alloc(u8, length);
        errdefer storage.allocator.free(bytes);
        const initialized = try storage.allocator.alloc(u8, bitmap_length);
        errdefer storage.allocator.free(initialized);
        @memset(initialized, 0);
        try storage.charge(charge);
        self.entries.appendAssumeCapacity(.{ .length = length, .alignment = alignment, .bytes = bytes, .initialized = initialized });
        return .{ .context = storage.context, .region = id };
    }

    pub fn range(self: *const Regions, storage: *const storage_mod.Storage, handle: Handle, offset: usize, length: usize, alignment: usize) !Range {
        const region = try self.get(storage, handle);
        if (alignment == 0 or !std.math.isPowerOfTwo(alignment) or alignment > region.alignment or offset % alignment != 0)
            return error.ExecutionInvalidAlignment;
        // Subtraction avoids accepting wrapped end addresses. Empty one-past
        // ranges are permitted but cannot authorize a nonempty typed access.
        if (offset > region.length or length > region.length - offset) return error.ExecutionIndexOutOfBounds;
        return .{ .handle = handle, .offset = offset, .length = length };
    }

    /// Copy reads instead of exporting a mutable host slice or an untracked
    /// language reference. Validate the entire range before touching output.
    pub fn read(self: *const Regions, storage: *const storage_mod.Storage, handle: Handle, offset: usize, destination: []u8) !void {
        _ = try self.range(storage, handle, offset, destination.len, 1);
        const region = try self.get(storage, handle);
        for (offset..offset + destination.len) |index| {
            const mask = @as(u8, 1) << @as(u3, @intCast(index % 8));
            if (region.initialized[index / 8] & mask == 0) return error.ExecutionUninitializedStorage;
        }
        @memcpy(destination, region.bytes[offset..][0..destination.len]);
    }

    pub fn write(self: *Regions, storage: *const storage_mod.Storage, handle: Handle, offset: usize, source: []const u8) !void {
        _ = try self.range(storage, handle, offset, source.len, 1);
        const region = try self.get(storage, handle);
        @memcpy(region.bytes[offset..][0..source.len], source);
        for (offset..offset + source.len) |index|
            region.initialized[index / 8] |= @as(u8, 1) << @as(u3, @intCast(index % 8));
    }

    /// Checked physical scalar access is deliberately distinct from safe
    /// reference establishment. The compiler must supply a numeric layout;
    /// receipts and initialized bytes alone never establish language loans.
    pub fn loadInteger(self: *const Regions, storage: *const storage_mod.Storage, handle: Handle, offset: usize, layout: *const @import("../5_codegen/bytecode/numeric_layout.zig").Layout, endian: std.builtin.Endian) !i128 {
        if (layout.size > 8) return error.ExecutionInvalidReference;
        _ = try self.range(storage, handle, offset, layout.size, layout.alignment);
        var bytes: [8]u8 = undefined;
        try self.read(storage, handle, offset, bytes[0..layout.size]);
        return @import("../5_codegen/bytecode/numeric_layout.zig").decodeInteger(layout, bytes[0..layout.size], endian);
    }

    pub fn storeInteger(self: *Regions, storage: *const storage_mod.Storage, handle: Handle, offset: usize, layout: *const @import("../5_codegen/bytecode/numeric_layout.zig").Layout, value: i128, endian: std.builtin.Endian) !void {
        if (layout.size > 8) return error.ExecutionInvalidReference;
        _ = try self.range(storage, handle, offset, layout.size, layout.alignment);
        var bytes: [8]u8 = undefined;
        try @import("../5_codegen/bytecode/numeric_layout.zig").encodeInteger(layout, value, bytes[0..layout.size], endian);
        try self.write(storage, handle, offset, bytes[0..layout.size]);
    }

    pub fn release(self: *Regions, storage: *const storage_mod.Storage, handle: Handle) !void {
        _ = try self.get(storage, handle);
        self.entries.items[@intFromEnum(handle.region)].live = false;
        // Quotas account for cumulative work/retained arena memory. Releasing
        // a receipt does not refund that budget or reuse its identity.
    }

    fn get(self: *const Regions, storage: *const storage_mod.Storage, handle: Handle) !Region {
        if (handle.context != storage.context) return error.ExecutionForeignReference;
        const index = @intFromEnum(handle.region);
        if (index >= self.entries.items.len) return error.ExecutionInvalidAcquisition;
        const region = self.entries.items[index];
        if (!region.live) return error.ExecutionReleasedAcquisition;
        return region;
    }
};

test "acquired regions enforce extent alignment lifetime and execution identity" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var storage = try storage_mod.Storage.init(arena.allocator(), 100);
    var regions: Regions = .{};
    const handle = try regions.acquire(&storage, 16, 8);
    _ = try regions.range(&storage, handle, 8, 8, 8);
    _ = try regions.range(&storage, handle, 16, 0, 8);
    try std.testing.expectError(error.ExecutionIndexOutOfBounds, regions.range(&storage, handle, 16, 1, 1));
    try std.testing.expectError(error.ExecutionIndexOutOfBounds, regions.range(&storage, handle, 1, std.math.maxInt(usize), 1));
    try std.testing.expectError(error.ExecutionInvalidAlignment, regions.range(&storage, handle, 1, 1, 8));
    try std.testing.expectError(error.ExecutionInvalidAlignment, regions.range(&storage, handle, 0, 1, 16));
    try std.testing.expectError(error.ExecutionInvalidAlignment, regions.acquire(&storage, 1, 3));
    try regions.release(&storage, handle);
    try std.testing.expectError(error.ExecutionReleasedAcquisition, regions.range(&storage, handle, 0, 0, 1));
    try std.testing.expectError(error.ExecutionReleasedAcquisition, regions.release(&storage, handle));
    const next = try regions.acquire(&storage, 0, 1);
    try std.testing.expect(next.region != handle.region);
    const consumed = storage.cells;
    try std.testing.expectError(error.ExecutionMemoryLimit, regions.acquire(&storage, 100, 1));
    try std.testing.expectEqual(consumed, storage.cells);
    try std.testing.expectEqual(@as(usize, 2), regions.entries.items.len);
    var other = try storage_mod.Storage.init(arena.allocator(), 100);
    try std.testing.expectError(error.ExecutionForeignReference, regions.range(&other, next, 0, 0, 1));
}

fn failedAcquisition(a: std.mem.Allocator) !void {
    // Execution storage normally has arena lifetime. Inject failures into that
    // arena's backing allocator, including metadata growth before publication.
    var arena = std.heap.ArenaAllocator.init(a);
    defer arena.deinit();
    var storage = try storage_mod.Storage.init(arena.allocator(), 100);
    var regions: Regions = .{};
    const handle = regions.acquire(&storage, 16, 8) catch |err| {
        try std.testing.expectEqual(@as(usize, 0), regions.entries.items.len);
        try std.testing.expectEqual(@as(usize, 0), storage.cells);
        return err;
    };
    _ = try regions.range(&storage, handle, 0, 16, 8);
    try regions.release(&storage, handle);
}

test "acquisition allocation failures publish neither receipts nor charges" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, failedAcquisition, .{});
}

test "acquired byte backing validates complete reads before publishing bytes" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var storage = try storage_mod.Storage.init(arena.allocator(), 100);
    var regions: Regions = .{};
    const handle = try regions.acquire(&storage, 17, 8);
    var output = [_]u8{99} ** 17;
    try std.testing.expectError(error.ExecutionUninitializedStorage, regions.read(&storage, handle, 0, &output));
    try regions.write(&storage, handle, 7, &.{ 41, 42, 43 });
    try std.testing.expectError(error.ExecutionUninitializedStorage, regions.read(&storage, handle, 6, output[0..4]));
    try std.testing.expectEqualSlices(u8, &(@as([17]u8, @splat(99))), &output);
    try regions.read(&storage, handle, 7, output[0..3]);
    try std.testing.expectEqualSlices(u8, &.{ 41, 42, 43 }, output[0..3]);
    try std.testing.expectError(error.ExecutionIndexOutOfBounds, regions.write(&storage, handle, 16, &.{ 1, 2 }));
    try std.testing.expectError(error.ExecutionUninitializedStorage, regions.read(&storage, handle, 16, output[0..1]));
    try regions.write(&storage, handle, 16, &.{7});
    try regions.read(&storage, handle, 16, output[0..1]);
    try std.testing.expectEqual(@as(u8, 7), output[0]);
    try regions.read(&storage, handle, 17, output[0..0]);
    try regions.release(&storage, handle);
    try std.testing.expectError(error.ExecutionReleasedAcquisition, regions.read(&storage, handle, 16, output[0..1]));
    try std.testing.expectError(error.ExecutionReleasedAcquisition, regions.write(&storage, handle, 0, &.{1}));
}

test "acquired scalar access shares layouts without manufacturing initialization" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var storage = try storage_mod.Storage.init(arena.allocator(), 100);
    var regions: Regions = .{};
    const handle = try regions.acquire(&storage, 16, 8);
    const numeric = @import("../5_codegen/bytecode/numeric_layout.zig");
    const layout: numeric.Layout = .{ .size = 4, .alignment = 4, .shape = .{ .integer = .{ .signed = true } } };
    try std.testing.expectError(error.ExecutionUninitializedStorage, regions.loadInteger(&storage, handle, 4, &layout, .little));
    try std.testing.expectError(error.ExecutionIntegerOutOfRange, regions.storeInteger(&storage, handle, 4, &layout, std.math.maxInt(i32) + @as(i128, 1), .little));
    try std.testing.expectError(error.ExecutionUninitializedStorage, regions.loadInteger(&storage, handle, 4, &layout, .little));
    try regions.storeInteger(&storage, handle, 4, &layout, -2, .big);
    try std.testing.expectEqual(@as(i128, -2), try regions.loadInteger(&storage, handle, 4, &layout, .big));
    var bytes: [4]u8 = undefined;
    try regions.read(&storage, handle, 4, &bytes);
    try std.testing.expectEqualSlices(u8, &.{ 255, 255, 255, 254 }, &bytes);
    try std.testing.expectError(error.ExecutionInvalidAlignment, regions.loadInteger(&storage, handle, 1, &layout, .big));
    try regions.release(&storage, handle);
    try std.testing.expectError(error.ExecutionReleasedAcquisition, regions.loadInteger(&storage, handle, 4, &layout, .big));
}
