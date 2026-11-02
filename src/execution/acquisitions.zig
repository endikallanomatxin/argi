const std = @import("std");
const storage_mod = @import("storage.zig");
const v = @import("../5_codegen/bytecode/value.zig");

pub const RegionId = enum(u32) { _ };
pub const Handle = struct { context: v.ContextId, region: RegionId };
pub const Range = struct { handle: Handle, offset: usize, length: usize };
const Region = struct { address: usize, length: usize, alignment: usize, bytes: []u8, initialized: []u8, live: bool = true };

// Virtual byte addresses are process-unique tokens, never native pointers.
// Include an unused byte after each range so one-past and empty addresses can
// never become the start of another allocation, even across context resets.
var next_address = std.atomic.Value(usize).init(1);

fn reserveAddress(length: usize, alignment: usize) !usize {
    var next = next_address.load(.monotonic);
    while (true) {
        const padded = std.math.add(usize, next, alignment - 1) catch return error.ExecutionAddressLimit;
        const base = padded & ~(alignment - 1);
        const end = std.math.add(usize, base, @max(length, 1)) catch return error.ExecutionAddressLimit;
        const following = std.math.add(usize, end, 1) catch return error.ExecutionAddressLimit;
        next = next_address.cmpxchgWeak(next, following, .monotonic, .monotonic) orelse return base;
    }
}

/// Concrete acquisition identities, separate from lexical slots and host
/// addresses. A receipt proves a live byte extent, never initialized typed data
/// or a language borrow. Released entries remain tombstones until context reset.
/// The execution arena owns the table and byte backing. Initialization bits
/// describe concrete bytes only, without reproducing static lifetime proofs.
pub const Regions = struct {
    entries: std.ArrayList(Region) = .empty,
    context: ?v.ContextId = null,

    pub fn acquire(self: *Regions, storage: *storage_mod.Storage, length: usize, alignment: usize) !Handle {
        if (self.context) |owner| if (owner != storage.context) return error.ExecutionForeignReference;
        if (alignment == 0 or !std.math.isPowerOfTwo(alignment)) return error.ExecutionInvalidAlignment;
        const id: RegionId = @enumFromInt(std.math.cast(u32, self.entries.items.len) orelse return error.ExecutionAcquisitionLimit);
        const bitmap_length = length / 8 + @intFromBool(length % 8 != 0);
        const charge = std.math.add(usize, std.math.add(usize, length, bitmap_length) catch return error.ExecutionMemoryLimit, 1) catch return error.ExecutionMemoryLimit;
        // Check the quota before allocating large backing, then reserve every
        // allocation before charging or publishing the complete acquisition.
        if (charge > storage.limit -| storage.cells) return error.ExecutionMemoryLimit;
        try self.entries.ensureUnusedCapacity(storage.bookkeepingAllocator(), 1);
        const bytes = try storage.allocator.alloc(u8, length);
        errdefer storage.allocator.free(bytes);
        const initialized = try storage.allocator.alloc(u8, bitmap_length);
        errdefer storage.allocator.free(initialized);
        @memset(initialized, 0);
        const address_ = try reserveAddress(length, alignment);
        try storage.charge(charge);
        self.entries.appendAssumeCapacity(.{ .address = address_, .length = length, .alignment = alignment, .bytes = bytes, .initialized = initialized });
        self.context = storage.context;
        return .{ .context = storage.context, .region = id };
    }

    /// Raw address transport retains byte arithmetic without exposing a host
    /// pointer. It supplies no safe-reference validity or acquisition authority.
    pub fn address(self: *const Regions, storage: *const storage_mod.Storage, handle: Handle, offset: usize) !usize {
        const region = try self.get(storage, handle);
        if (offset > region.length) return error.ExecutionIndexOutOfBounds;
        return region.address + offset;
    }

    /// Recover only the concrete region and checked byte range. Establishing a
    /// language reference still requires compiler-selected acquisition evidence.
    pub fn resolveAddress(self: *const Regions, storage: *const storage_mod.Storage, address_: usize, length: usize, alignment: usize) !Range {
        if (self.context == null or self.context.? != storage.context) return error.ExecutionForeignReference;
        var low: usize = 0;
        var high = self.entries.items.len;
        while (low < high) {
            const middle = low + (high - low) / 2;
            if (self.entries.items[middle].address <= address_) low = middle + 1 else high = middle;
        }
        if (low == 0) return error.ExecutionInvalidAcquisition;
        const index = low - 1;
        const region = self.entries.items[index];
        const offset = address_ - region.address;
        // Reject gaps before inspecting liveness, to avoid attributing a token
        // outside this region to its previous, possibly released allocation.
        if (offset > region.length) return error.ExecutionInvalidAcquisition;
        return self.range(storage, .{ .context = storage.context, .region = @enumFromInt(@as(u32, @intCast(index))) }, offset, length, alignment);
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

    /// Resolve the acquisition named by a checked receipt, then select within
    /// its granted extent. A different live region at the requested address
    /// cannot substitute for that acquisition. This grants no typed occupancy.
    pub fn resolveReceipt(self: *const Regions, storage: *const storage_mod.Storage, receipt: @import("../5_codegen/bytecode/acquired_receipt.zig").Bounds, address_: usize, length: usize, alignment: usize) !Range {
        const backing = try self.resolveAddress(storage, receipt.address, receipt.size, receipt.alignment);
        if (length > try receipt.remaining(address_)) return error.ExecutionIndexOutOfBounds;
        const offset = address_ - receipt.address;
        return self.range(storage, backing.handle, try std.math.add(usize, backing.offset, offset), length, alignment);
    }

    /// Copy reads instead of exporting a mutable host slice or an untracked
    /// language reference. Validate the entire range before touching output.
    pub fn requireInitialized(self: *const Regions, storage: *const storage_mod.Storage, handle: Handle, offset: usize, length: usize) !void {
        _ = try self.range(storage, handle, offset, length, 1);
        const region = try self.get(storage, handle);
        for (offset..offset + length) |index| {
            const mask = @as(u8, 1) << @as(u3, @intCast(index % 8));
            if (region.initialized[index / 8] & mask == 0) return error.ExecutionUninitializedStorage;
        }
    }

    pub fn read(self: *const Regions, storage: *const storage_mod.Storage, handle: Handle, offset: usize, destination: []u8) !void {
        try self.requireInitialized(storage, handle, offset, destination.len);
        const region = try self.get(storage, handle);
        @memcpy(destination, region.bytes[offset..][0..destination.len]);
    }

    pub fn write(self: *Regions, storage: *storage_mod.Storage, handle: Handle, offset: usize, source: []const u8) !void {
        _ = try self.range(storage, handle, offset, source.len, 1);
        const region = try self.get(storage, handle);
        try storage.invalidateAcquiredReferences(handle, offset, source.len);
        @memcpy(region.bytes[offset..][0..source.len], source);
        for (offset..offset + source.len) |index|
            region.initialized[index / 8] |= @as(u8, 1) << @as(u3, @intCast(index % 8));
    }

    // Replacing an opaque representation makes its bytes unavailable. Retained
    // reference evidence is published separately by the prepared typed write;
    // stale bytes must not appear to encode that new reference.
    pub fn forgetBytes(self: *Regions, storage: *storage_mod.Storage, handle: Handle, offset: usize, length: usize) !void {
        _ = try self.range(storage, handle, offset, length, 1);
        const region = try self.get(storage, handle);
        try storage.invalidateAcquiredReferences(handle, offset, length);
        for (offset..offset + length) |index|
            region.initialized[index / 8] &= ~(@as(u8, 1) << @as(u3, @intCast(index % 8)));
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

    pub fn storeInteger(self: *Regions, storage: *storage_mod.Storage, handle: Handle, offset: usize, layout: *const @import("../5_codegen/bytecode/numeric_layout.zig").Layout, value: i128, endian: std.builtin.Endian) !void {
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
        if (self.context == null or self.context.? != storage.context or handle.context != storage.context) return error.ExecutionForeignReference;
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

test "acquired receipts bound selection to their own live granted region" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var storage = try storage_mod.Storage.init(arena.allocator(), 4096);
    const handle = try storage.acquisitions.acquire(&storage, 32, 8);
    const base = try storage.acquisitions.address(&storage, handle, 0);
    const receipt: @import("../5_codegen/bytecode/acquired_receipt.zig").Bounds = .{ .address = base + 8, .size = 16, .alignment = 8 };
    const selected = try storage.acquisitions.resolveReceipt(&storage, receipt, base + 12, 4, 4);
    try std.testing.expectEqual(handle, selected.handle);
    try std.testing.expectEqual(@as(usize, 12), selected.offset);
    _ = try storage.acquisitions.resolveReceipt(&storage, receipt, base + 24, 0, 8);
    try std.testing.expectError(error.ExecutionIndexOutOfBounds, storage.acquisitions.resolveReceipt(&storage, receipt, base + 4, 4, 4));
    try std.testing.expectError(error.ExecutionIndexOutOfBounds, storage.acquisitions.resolveReceipt(&storage, receipt, base + 24, 1, 1));
    try std.testing.expectError(error.ExecutionInvalidAlignment, storage.acquisitions.resolveReceipt(&storage, receipt, base + 9, 4, 4));
    const other = try storage.acquisitions.acquire(&storage, 32, 8);
    const other_address = try storage.acquisitions.address(&storage, other, 0);
    try std.testing.expectError(error.ExecutionIndexOutOfBounds, storage.acquisitions.resolveReceipt(&storage, receipt, other_address, 4, 4));
    var expanded = receipt;
    expanded.size = 32;
    try std.testing.expectError(error.ExecutionIndexOutOfBounds, storage.acquisitions.resolveReceipt(&storage, expanded, base + 8, 4, 4));
    try storage.acquisitions.release(&storage, handle);
    try std.testing.expectError(error.ExecutionReleasedAcquisition, storage.acquisitions.resolveReceipt(&storage, receipt, base + 12, 4, 4));
    var foreign = try storage_mod.Storage.init(arena.allocator(), 4096);
    try std.testing.expectError(error.ExecutionForeignReference, storage.acquisitions.resolveReceipt(&foreign, receipt, base + 12, 4, 4));
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

test "virtual acquisition addresses preserve offsets and never alias another context" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var storage = try storage_mod.Storage.init(arena.allocator(), 100);
    var regions: Regions = .{};
    const first = try regions.acquire(&storage, 16, 16);
    const base = try regions.address(&storage, first, 0);
    try std.testing.expectEqual(@as(usize, 0), base % 16);
    const inside = try regions.resolveAddress(&storage, base + 8, 8, 8);
    try std.testing.expectEqualDeep(first, inside.handle);
    try std.testing.expectEqual(@as(usize, 8), inside.offset);
    _ = try regions.resolveAddress(&storage, base + 16, 0, 1);
    try std.testing.expectError(error.ExecutionIndexOutOfBounds, regions.resolveAddress(&storage, base + 16, 1, 1));
    try std.testing.expectError(error.ExecutionInvalidAlignment, regions.resolveAddress(&storage, base + 1, 1, 8));
    const empty = try regions.acquire(&storage, 0, 1);
    const empty_address = try regions.address(&storage, empty, 0);
    try std.testing.expect(empty_address > base + 16);
    try std.testing.expectError(error.ExecutionInvalidAcquisition, regions.resolveAddress(&storage, empty_address + 1, 0, 1));
    try regions.release(&storage, first);
    try std.testing.expectError(error.ExecutionReleasedAcquisition, regions.resolveAddress(&storage, base + 8, 1, 1));
    var other = try storage_mod.Storage.init(arena.allocator(), 100);
    try std.testing.expectError(error.ExecutionForeignReference, regions.resolveAddress(&other, base, 1, 1));
    try std.testing.expectError(error.ExecutionForeignReference, regions.acquire(&other, 1, 1));
    var other_regions: Regions = .{};
    const fresh = try other_regions.acquire(&other, 16, 16);
    try std.testing.expect((try other_regions.address(&other, fresh, 0)) != base);
    try std.testing.expectError(error.ExecutionInvalidAcquisition, other_regions.resolveAddress(&other, base, 1, 1));
}

test "acquired receipts preserve public grant restrictions inside authenticated bounds" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var storage = try storage_mod.Storage.init(arena.allocator(), 4096);
    const handle = try storage.acquisitions.acquire(&storage, 32, 8);
    const base = try storage.acquisitions.address(&storage, handle, 0);
    var receipt: @import("../5_codegen/bytecode/acquired_receipt.zig").Bounds = .{
        .address = base,
        .size = 32,
        .alignment = 8,
        .grant = .{ .address = base + 8, .size = 8 },
    };
    const selected = try storage.acquisitions.resolveReceipt(&storage, receipt, base + 12, 4, 4);
    try std.testing.expectEqual(@as(usize, 12), selected.offset);
    try std.testing.expectError(error.ExecutionIndexOutOfBounds, storage.acquisitions.resolveReceipt(&storage, receipt, base + 4, 4, 4));
    try std.testing.expectError(error.ExecutionIndexOutOfBounds, storage.acquisitions.resolveReceipt(&storage, receipt, base + 16, 4, 4));
    receipt.grant.?.size = 32;
    _ = try storage.acquisitions.resolveReceipt(&storage, receipt, base + 12, 4, 4);
    try std.testing.expectEqual(@as(usize, 20), try receipt.remaining(base + 12));
    try std.testing.expectError(error.ExecutionIndexOutOfBounds, storage.acquisitions.resolveReceipt(&storage, receipt, base + 32, 4, 4));
    receipt.grant = .{ .address = base - 1, .size = 1 };
    try std.testing.expectError(error.ExecutionIndexOutOfBounds, storage.acquisitions.resolveReceipt(&storage, receipt, base, 1, 1));
}
