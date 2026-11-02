const std = @import("std");

/// An index over semantic identities, with allocation-free rollback. Keys and
/// IDs are plain borrowed data; resource-owning values do not belong here.
/// Checkpoints are undo positions and may nest. Publication discards history.
pub fn IdentityCache(comptime Key: type, comptime Id: type) type {
    if (@typeInfo(Id) != .@"enum") @compileError("IdentityCache values must be typed IDs");
    return struct {
        const Self = @This();
        const Map = std.AutoHashMapUnmanaged(Key, Id);
        const Undo = struct { key: Key, previous: ?Id };
        pub const empty: Self = .{};
        map: Map = .empty,
        undo: std.ArrayList(Undo) = .empty,

        pub fn get(self: *const Self, key: Key) ?Id {
            return self.map.get(key);
        }

        pub fn count(self: *const Self) usize {
            return self.map.count();
        }

        pub fn put(self: *Self, allocator: std.mem.Allocator, key: Key, id: Id) !void {
            const previous = self.map.get(key);
            if (previous == id) return;
            // Either allocation may fail. Neither failure may publish a value
            // that has no corresponding undo entry.
            try self.undo.ensureUnusedCapacity(allocator, 1);
            try self.map.put(allocator, key, id);
            self.undo.appendAssumeCapacity(.{ .key = key, .previous = previous });
        }

        pub fn checkpoint(self: *const Self) usize {
            return self.undo.items.len;
        }

        pub fn rollback(self: *Self, saved: usize) void {
            std.debug.assert(saved <= self.undo.items.len);
            while (self.undo.items.len > saved) {
                const entry = self.undo.pop().?;
                if (entry.previous) |id| {
                    // Forward operations only publish values. An overwritten
                    // key remains present until its insert is itself undone.
                    self.map.getPtr(entry.key).?.* = id;
                } else std.debug.assert(self.map.remove(entry.key));
            }
        }

        pub fn commit(self: *Self, allocator: std.mem.Allocator) void {
            self.undo.deinit(allocator);
            self.undo = .empty;
        }

        /// Destructive reset, invalidating every outstanding checkpoint.
        pub fn clearRetainingCapacity(self: *Self) void {
            self.map.clearRetainingCapacity();
            self.undo.clearRetainingCapacity();
        }

        pub fn clone(self: *const Self, allocator: std.mem.Allocator) !Self {
            var result: Self = .{};
            errdefer result.deinit(allocator);
            result.map = try self.map.clone(allocator);
            try result.undo.appendSlice(allocator, self.undo.items);
            return result;
        }

        pub fn deinit(self: *Self, allocator: std.mem.Allocator) void {
            self.map.deinit(allocator);
            self.undo.deinit(allocator);
            self.* = .{};
        }
    };
}

const TestId = enum(u32) { _ };
const TestCache = IdentityCache(u32, TestId);

test "identity cache restores overwritten and inserted keys through nested checkpoints" {
    const a = std.testing.allocator;
    var cache: TestCache = .{};
    defer cache.deinit(a);
    try cache.put(a, 1, @enumFromInt(10));
    cache.commit(a);
    const outer = cache.checkpoint();
    try cache.put(a, 1, @enumFromInt(20));
    const inner = cache.checkpoint();
    try cache.put(a, 1, @enumFromInt(30));
    for (2..128) |key| try cache.put(a, @intCast(key), @enumFromInt(key));
    cache.rollback(inner);
    try std.testing.expectEqual(@as(TestId, @enumFromInt(20)), cache.get(1).?);
    try std.testing.expectEqual(@as(usize, 1), cache.count());
    try cache.put(a, 2, @enumFromInt(40));
    cache.rollback(outer);
    try std.testing.expectEqual(@as(TestId, @enumFromInt(10)), cache.get(1).?);
    try std.testing.expectEqual(@as(usize, 1), cache.count());
}

test "identity cache publication and clone remain reversible after allocation failure" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, struct {
        fn run(a: std.mem.Allocator) !void {
            var cache: TestCache = .{};
            defer cache.deinit(a);
            try cache.put(a, 1, @enumFromInt(10));
            cache.commit(a);
            const saved = cache.checkpoint();
            errdefer {
                cache.rollback(saved);
                std.debug.assert(cache.count() == 1 and cache.get(1).? == @as(TestId, @enumFromInt(10)));
            }
            try cache.put(a, 1, @enumFromInt(20));
            try cache.put(a, 2, @enumFromInt(30));
            var copy = try cache.clone(a);
            defer copy.deinit(a);
            cache.rollback(saved);
            copy.rollback(saved);
            try std.testing.expectEqual(@as(TestId, @enumFromInt(10)), copy.get(1).?);
            try std.testing.expectEqual(@as(usize, 1), copy.count());
        }
    }.run, .{});
}

test "identity cache rejected unique keys retain bounded storage after warmup" {
    var accounting = std.testing.FailingAllocator.init(std.testing.allocator, .{});
    const a = accounting.allocator();
    var cache: TestCache = .{};
    defer cache.deinit(a);
    try cache.put(a, 1, @enumFromInt(10));
    cache.commit(a);
    var warm: usize = 0;
    for (0..1000) |index| {
        const saved = cache.checkpoint();
        try cache.put(a, 1, @enumFromInt(20));
        try cache.put(a, @intCast(index + 2), @enumFromInt(30));
        cache.rollback(saved);
        const live = accounting.allocated_bytes - accounting.freed_bytes;
        if (index == 0) warm = live else try std.testing.expectEqual(warm, live);
        try std.testing.expectEqual(@as(usize, 1), cache.count());
    }
}
