const std = @import("std");

/// Bounds live backing allocations without changing their layout or alignment.
/// Keep this adapter at a stable address while its allocator is in use.
pub const BoundedAllocator = struct {
    child: std.mem.Allocator,
    limit: usize,
    used: usize = 0,

    pub fn allocator(self: *BoundedAllocator) std.mem.Allocator {
        return .{ .ptr = self, .vtable = &.{ .alloc = alloc, .resize = resize, .remap = remap, .free = free } };
    }

    fn fits(self: *const BoundedAllocator, old: usize, new: usize) bool {
        return new <= old or new - old <= self.limit -| self.used;
    }

    fn alloc(context: *anyopaque, len: usize, alignment: std.mem.Alignment, ret: usize) ?[*]u8 {
        const self: *BoundedAllocator = @ptrCast(@alignCast(context));
        if (!self.fits(0, len)) return null;
        const memory = self.child.rawAlloc(len, alignment, ret) orelse return null;
        self.used += len;
        return memory;
    }

    fn resize(context: *anyopaque, memory: []u8, alignment: std.mem.Alignment, len: usize, ret: usize) bool {
        const self: *BoundedAllocator = @ptrCast(@alignCast(context));
        if (!self.fits(memory.len, len)) return false;
        if (!self.child.rawResize(memory, alignment, len, ret)) return false;
        self.used = self.used - memory.len + len;
        return true;
    }

    fn remap(context: *anyopaque, memory: []u8, alignment: std.mem.Alignment, len: usize, ret: usize) ?[*]u8 {
        const self: *BoundedAllocator = @ptrCast(@alignCast(context));
        if (!self.fits(memory.len, len)) return null;
        const result = self.child.rawRemap(memory, alignment, len, ret) orelse return null;
        self.used = self.used - memory.len + len;
        return result;
    }

    fn free(context: *anyopaque, memory: []u8, alignment: std.mem.Alignment, ret: usize) void {
        const self: *BoundedAllocator = @ptrCast(@alignCast(context));
        self.child.rawFree(memory, alignment, ret);
        self.used -= memory.len;
    }
};

test "bounded allocator rejects growth without consuming budget and reuses freed capacity" {
    var bounded = BoundedAllocator{ .child = std.testing.allocator, .limit = 64 };
    const allocator = bounded.allocator();
    const first = try allocator.alloc(u8, 48);
    try std.testing.expectError(error.OutOfMemory, allocator.alloc(u8, 17));
    try std.testing.expect(!allocator.rawResize(first, .@"1", 65, @returnAddress()));
    try std.testing.expect(allocator.rawRemap(first, .@"1", 65, @returnAddress()) == null);
    try std.testing.expectEqual(@as(usize, 48), bounded.used);
    allocator.free(first);
    try std.testing.expectEqual(@as(usize, 0), bounded.used);
    const second = try allocator.alloc(u8, 64);
    allocator.free(second);
    try std.testing.expectEqual(@as(usize, 0), bounded.used);
}

test "bounded allocator accounts for successful resize and remap" {
    var storage: [256]u8 = undefined;
    var backing = std.heap.FixedBufferAllocator.init(&storage);
    var bounded = BoundedAllocator{ .child = backing.allocator(), .limit = 128 };
    const allocator = bounded.allocator();
    const memory = try allocator.alloc(u8, 32);
    try std.testing.expect(allocator.rawResize(memory, .@"1", 64, @returnAddress()));
    try std.testing.expectEqual(@as(usize, 64), bounded.used);
    const remapped = allocator.rawRemap(memory.ptr[0..64], .@"1", 96, @returnAddress()).?;
    try std.testing.expectEqual(@as(usize, 96), bounded.used);
    try std.testing.expect(allocator.rawResize(remapped[0..96], .@"1", 16, @returnAddress()));
    try std.testing.expectEqual(@as(usize, 16), bounded.used);
    const final: []u8 = remapped[0..16];
    allocator.free(final);
    try std.testing.expectEqual(@as(usize, 0), bounded.used);
}
