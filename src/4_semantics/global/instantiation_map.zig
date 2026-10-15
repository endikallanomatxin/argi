const std = @import("std");

/// Instance-local ID translation. Module IDs remain direct indexes, while
/// untouched regions need no value storage or initialization.
pub fn Map(comptime Value: type) type {
    return struct {
        const Self = @This();
        const page_len = 128;
        const Page = [page_len]?Value;

        limit: usize,
        pages: []?*Page = &.{},

        pub fn init(limit: usize) Self {
            return .{ .limit = limit };
        }

        pub fn deinit(self: *Self, allocator: std.mem.Allocator) void {
            for (self.pages) |page| if (page) |values| allocator.destroy(values);
            allocator.free(self.pages);
            self.* = undefined;
        }

        pub fn get(self: *const Self, index: usize) ?Value {
            std.debug.assert(index < self.limit);
            if (self.pages.len == 0) return null;
            const page = self.pages[index / page_len] orelse return null;
            return page[index % page_len];
        }

        pub fn put(self: *Self, allocator: std.mem.Allocator, index: usize, value: Value) !void {
            std.debug.assert(index < self.limit);
            if (self.pages.len == 0) {
                self.pages = try allocator.alloc(?*Page, (self.limit - 1) / page_len + 1);
                @memset(self.pages, null);
            }
            const slot = &self.pages[index / page_len];
            if (slot.* == null) {
                const page = try allocator.create(Page);
                @memset(page, null);
                slot.* = page;
            }
            slot.*.?[index % page_len] = value;
        }
    };
}

test "instantiation maps preserve sparse IDs and existing pages on allocation failure" {
    const Id = enum(u32) { _ };
    var failing = std.testing.FailingAllocator.init(std.testing.allocator, .{});
    const allocator = failing.allocator();
    var map = Map(Id).init(10000);
    defer map.deinit(allocator);
    try std.testing.expectEqual(null, map.get(9999));
    try map.put(allocator, 0, @enumFromInt(0));
    failing.fail_index = failing.alloc_index;
    try map.put(allocator, 127, @enumFromInt(1));
    try std.testing.expectError(error.OutOfMemory, map.put(allocator, 128, @enumFromInt(2)));
    try std.testing.expectEqual(@as(?Id, @enumFromInt(0)), map.get(0));
    try std.testing.expectEqual(@as(?Id, @enumFromInt(1)), map.get(127));
    try std.testing.expectEqual(null, map.get(128));
    failing.fail_index = std.math.maxInt(usize);
    try map.put(allocator, 128, @enumFromInt(2));
    try map.put(allocator, 9999, @enumFromInt(3));
    try std.testing.expectEqual(@as(?Id, @enumFromInt(2)), map.get(128));
    try std.testing.expectEqual(@as(?Id, @enumFromInt(3)), map.get(9999));
    try std.testing.expectEqual(null, map.get(4096));
}

test "instantiation map allocation failures release partial directories" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, struct {
        fn exercise(allocator: std.mem.Allocator) !void {
            var map = Map(u32).init(10000);
            defer map.deinit(allocator);
            try map.put(allocator, 1, 10);
            try map.put(allocator, 9999, 20);
        }
    }.exercise, .{});
}
