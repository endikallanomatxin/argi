const std = @import("std");

/// Only owned messages and token arrays cross the worker boundary. The semantic
/// graph and its allocator-backed caches stay exclusively on the worker.
pub const Background = struct {
    allocator: std.mem.Allocator,
    io: std.Io,
    mutex: std.Io.Mutex = .init,
    output_mutex: std.Io.Mutex = .init,
    ready: std.Io.Condition = .init,
    jobs: std.ArrayList(Job) = .empty,
    stopped: bool = false,
    generation: u64 = 0,
    tokens: std.StringHashMapUnmanaged([]u32) = .empty,

    pub const Job = struct {
        payload: []u8,
        generation: u64,
        change_uri: ?[]u8 = null,
    };

    pub fn deinit(self: *Background) void {
        for (self.jobs.items) |job| self.freeJob(job);
        self.jobs.deinit(self.allocator);
        self.clearTokens();
        self.tokens.deinit(self.allocator);
    }

    fn clearTokens(self: *Background) void {
        var it = self.tokens.iterator();
        while (it.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
            self.allocator.free(entry.value_ptr.*);
        }
        self.tokens.clearRetainingCapacity();
    }

    pub fn freeJob(self: *Background, job: Job) void {
        self.allocator.free(job.payload);
        if (job.change_uri) |uri| self.allocator.free(uri);
    }

    pub fn enqueue(self: *Background, payload: []const u8, edited: bool, change_uri: ?[]const u8) !void {
        const owned = try self.allocator.dupe(u8, payload);
        errdefer self.allocator.free(owned);
        const uri = if (change_uri) |value| try self.allocator.dupe(u8, value) else null;
        errdefer if (uri) |value| self.allocator.free(value);
        self.mutex.lockUncancelable(self.io);
        defer self.mutex.unlock(self.io);
        try self.jobs.ensureUnusedCapacity(self.allocator, 1);
        if (edited) {
            self.generation += 1;
            self.clearTokens();
        }
        const job: Job = .{ .payload = owned, .generation = self.generation, .change_uri = uri };
        // Full-sync edits supersede consecutive unprocessed edits to the same
        // buffer. Requests and document lifecycle messages remain FIFO barriers.
        if (uri) |value| if (self.jobs.items.len > 0) {
            const previous = &self.jobs.items[self.jobs.items.len - 1];
            if (previous.change_uri) |old| if (std.mem.eql(u8, old, value)) {
                self.freeJob(previous.*);
                previous.* = job;
                self.ready.signal(self.io);
                return;
            };
        };
        self.jobs.appendAssumeCapacity(job);
        self.ready.signal(self.io);
    }

    pub fn next(self: *Background) ?Job {
        self.mutex.lockUncancelable(self.io);
        defer self.mutex.unlock(self.io);
        while (self.jobs.items.len == 0 and !self.stopped) self.ready.waitUncancelable(self.io, &self.mutex);
        if (self.jobs.items.len == 0) return null;
        return self.jobs.orderedRemove(0);
    }

    pub fn stop(self: *Background) void {
        self.mutex.lockUncancelable(self.io);
        defer self.mutex.unlock(self.io);
        self.stopped = true;
        self.ready.signal(self.io);
    }

    pub fn current(self: *Background, generation: u64) bool {
        self.mutex.lockUncancelable(self.io);
        defer self.mutex.unlock(self.io);
        return generation == self.generation;
    }

    pub fn publishTokens(self: *Background, uri: []const u8, generation: u64, data: []const u32) !bool {
        self.mutex.lockUncancelable(self.io);
        defer self.mutex.unlock(self.io);
        if (generation != self.generation) return false;
        const copy = try self.allocator.dupe(u32, data);
        errdefer self.allocator.free(copy);
        if (self.tokens.getPtr(uri)) |previous| {
            self.allocator.free(previous.*);
            previous.* = copy;
        } else {
            const key = try self.allocator.dupe(u8, uri);
            errdefer self.allocator.free(key);
            try self.tokens.put(self.allocator, key, copy);
        }
        return true;
    }

    pub fn copyTokens(self: *Background, allocator: std.mem.Allocator, uri: []const u8) !?[]u32 {
        self.mutex.lockUncancelable(self.io);
        defer self.mutex.unlock(self.io);
        return if (self.tokens.get(uri)) |data| try allocator.dupe(u32, data) else null;
    }
};

test "LSP background coalesces edits, preserves requests and rejects stale tokens" {
    const a = std.testing.allocator;
    var worker: Background = .{ .allocator = a, .io = std.testing.io };
    defer worker.deinit();
    try worker.enqueue("first", true, "file:///a");
    try worker.enqueue("second", true, "file:///a");
    try std.testing.expectEqual(@as(usize, 1), worker.jobs.items.len);
    try std.testing.expect(!try worker.publishTokens("file:///a", 1, &.{1}));
    try std.testing.expect(try worker.publishTokens("file:///a", 2, &.{2}));
    const data = (try worker.copyTokens(a, "file:///a")).?;
    defer a.free(data);
    try std.testing.expectEqualSlices(u32, &.{2}, data);
    try worker.enqueue("request", false, null);
    try worker.enqueue("third", true, "file:///a");
    try std.testing.expectEqual(@as(usize, 3), worker.jobs.items.len);
    try std.testing.expectEqual(@as(?[]u32, null), try worker.copyTokens(a, "file:///a"));
    worker.stop();
    const expected = [_][]const u8{ "second", "request", "third" };
    for (expected) |payload| {
        const job = worker.next().?;
        defer worker.freeJob(job);
        try std.testing.expectEqualStrings(payload, job.payload);
    }
    try std.testing.expect(worker.next() == null);
}
