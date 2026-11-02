//! Fixture ownership determines worker assignment; test bodies are opaque to us.
const std = @import("std");

pub fn groupIndex(namespaces: *const std.StringHashMap(usize), name: []const u8) ?usize {
    var position: usize = 0;
    while (std.mem.indexOfPos(u8, name, position, ".test.")) |separator| {
        if (namespaces.get(name[0 .. separator + ".test.".len])) |index| return index;
        position = separator + 1;
    }
    return null;
}

pub fn workerFor(fixture: []const u8, workers: u32) u32 {
    std.debug.assert(workers != 0);
    return @intCast(std.hash.Wyhash.hash(0, fixture) % workers);
}

pub fn selected(fixture: ?[]const u8, exclusive: bool, shard: []const u8, workers: u32) !bool {
    if (std.mem.eql(u8, shard, "all")) return true;
    if (std.mem.eql(u8, shard, "serial")) return exclusive;
    const worker = try std.fmt.parseUnsigned(u32, shard, 10);
    if (worker >= workers) return error.InvalidShard;
    if (exclusive) return false;
    return workerFor(fixture orelse return error.MissingFixtureGroup, workers) == worker;
}

pub fn verifyIsolation() !void {
    var namespaces: std.StringHashMap(usize) = .init(std.testing.allocator);
    defer namespaces.deinit();
    try namespaces.put("fixtures.first.test.test.", 0);
    try namespaces.put("fixtures.second.test.test.", 1);
    try std.testing.expectEqual(@as(?usize, 0), groupIndex(&namespaces, "fixtures.first.test.test.same title"));
    try std.testing.expectEqual(@as(?usize, 1), groupIndex(&namespaces, "fixtures.second.test.test.same title"));
    try std.testing.expectEqual(@as(?usize, 1), groupIndex(&namespaces, "fixtures.second.test.test.title containing .test."));
    try std.testing.expectEqual(@as(?usize, null), groupIndex(&namespaces, "fixtures.unknown.test.test.same title"));
    for ([_]u32{ 1, 2, 4, 8, 16, 64 }) |workers| {
        var count: usize = 0;
        for (0..workers) |worker| {
            var buffer: [8]u8 = undefined;
            const shard = try std.fmt.bufPrint(&buffer, "{d}", .{worker});
            const fixture = "tests/feature_tests/execution/example";
            if (try selected(fixture, false, shard, workers)) count += 1;
            try std.testing.expect(!try selected(fixture, true, shard, workers));
        }
        try std.testing.expectEqual(@as(usize, 1), count);
    }
    try std.testing.expect(try selected(null, true, "serial", 16));
    try std.testing.expect(!try selected("example", false, "serial", 16));
    try std.testing.expect(try selected("example", false, "all", 1));
    try std.testing.expectError(error.MissingFixtureGroup, selected(null, false, "0", 1));
}
