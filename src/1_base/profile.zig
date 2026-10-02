const std = @import("std");

pub fn timestamp(io: ?std.Io) i96 {
    return if (io) |clock_io| std.Io.Timestamp.now(clock_io, .boot).nanoseconds else 0;
}

pub fn accumulate(io: ?std.Io, start: i96, elapsed_ns: *u64) void {
    if (io != null) elapsed_ns.* += @intCast(@max(0, timestamp(io) - start));
}

/// Count successful allocation requests, not allocator-resident memory. An
/// arena can retain a freed buffer, so these counters are not a peak-RSS metric.
pub const AllocationCounter = struct {
    child: std.mem.Allocator,
    requested_bytes: *u64,

    pub fn allocator(self: *AllocationCounter) std.mem.Allocator {
        return .{ .ptr = self, .vtable = &.{ .alloc = alloc, .resize = resize, .remap = remap, .free = free } };
    }

    fn alloc(context: *anyopaque, len: usize, alignment: std.mem.Alignment, ret_addr: usize) ?[*]u8 {
        const self: *AllocationCounter = @ptrCast(@alignCast(context));
        const result = self.child.rawAlloc(len, alignment, ret_addr) orelse return null;
        self.requested_bytes.* += len;
        return result;
    }

    fn resize(context: *anyopaque, memory: []u8, alignment: std.mem.Alignment, new_len: usize, ret_addr: usize) bool {
        const self: *AllocationCounter = @ptrCast(@alignCast(context));
        if (!self.child.rawResize(memory, alignment, new_len, ret_addr)) return false;
        if (new_len > memory.len) self.requested_bytes.* += new_len - memory.len;
        return true;
    }

    fn remap(context: *anyopaque, memory: []u8, alignment: std.mem.Alignment, new_len: usize, ret_addr: usize) ?[*]u8 {
        const self: *AllocationCounter = @ptrCast(@alignCast(context));
        const result = self.child.rawRemap(memory, alignment, new_len, ret_addr) orelse return null;
        if (new_len > memory.len) self.requested_bytes.* += new_len - memory.len;
        return result;
    }

    fn free(context: *anyopaque, memory: []u8, alignment: std.mem.Alignment, ret_addr: usize) void {
        const self: *AllocationCounter = @ptrCast(@alignCast(context));
        self.child.rawFree(memory, alignment, ret_addr);
    }
};
