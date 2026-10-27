//! Scheduling uses audited metadata, never the syntax of test implementations.
const std = @import("std");
const catalog = @import("fixture_catalog.zig");

pub fn workerFor(key: []const u8, workers: u32) u32 {
    std.debug.assert(workers != 0);
    return @intCast(std.hash.Wyhash.hash(0, key) % workers);
}

pub fn selected(entry: catalog.Entry, shard: []const u8, workers: u32) !bool {
    if (std.mem.eql(u8, shard, "all")) return true;
    if (std.mem.eql(u8, shard, "serial")) return entry.isolation == .exclusive;
    const worker = try std.fmt.parseUnsigned(u32, shard, 10);
    if (worker >= workers) return error.InvalidShard;
    return entry.isolation == .fixture and workerFor(entry.fixture orelse return error.MissingFixtureIsolationGroup, workers) == worker;
}
