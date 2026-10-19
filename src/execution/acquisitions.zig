const std = @import("std");
const storage_mod = @import("storage.zig");
const v = @import("../5_codegen/bytecode/value.zig");

pub const RegionId = enum(u32) { _ };
pub const Handle = struct { context: v.ContextId, region: RegionId };
pub const Range = struct { handle: Handle, offset: usize, length: usize };
const Region = struct { length: usize, alignment: usize, live: bool = true };

/// Concrete acquisition identities, separate from lexical slots and host
/// addresses. A receipt proves a live byte extent, never initialized typed data
/// or a language borrow. Released entries remain tombstones until context reset.
/// The execution arena owns this table; no per-region allocation is retained.
pub const Regions = struct {
    entries: std.ArrayList(Region) = .empty,

    pub fn acquire(self: *Regions, storage: *storage_mod.Storage, length: usize, alignment: usize) !Handle {
        if (alignment == 0 or !std.math.isPowerOfTwo(alignment)) return error.ExecutionInvalidAlignment;
        const id: RegionId = @enumFromInt(std.math.cast(u32, self.entries.items.len) orelse return error.ExecutionAcquisitionLimit);
        // Reserve before charging so allocation failure publishes no receipt.
        try self.entries.ensureUnusedCapacity(storage.allocator, 1);
        const charge = std.math.add(usize, length, 1) catch return error.ExecutionMemoryLimit;
        try storage.charge(charge);
        self.entries.appendAssumeCapacity(.{ .length = length, .alignment = alignment });
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
