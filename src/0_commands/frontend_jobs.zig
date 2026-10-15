const std = @import("std");

/// Execution policy only: never part of semantic identities or cache keys.
pub const Jobs = union(enum) {
    auto,
    count: usize,

    pub fn parse(text: []const u8) !Jobs {
        if (std.mem.eql(u8, text, "auto")) return .auto;
        const count = std.fmt.parseInt(usize, text, 10) catch return error.InvalidFrontendJobs;
        if (count == 0 or count > 256) return error.InvalidFrontendJobs;
        return .{ .count = count };
    }

    pub fn resolve(self: Jobs) usize {
        return switch (self) {
            .auto => forCpuCount(std.Thread.getCpuCount() catch 1),
            .count => |count| count,
        };
    }

    fn forCpuCount(cpus: usize) usize {
        return @max(1, @min(8, cpus / 2));
    }
};

test "automatic frontend jobs use half the available CPUs with conservative bounds" {
    for ([_]usize{ 0, 1, 2, 3, 4, 8, 12, 16, 64 }, [_]usize{ 1, 1, 1, 1, 2, 4, 6, 8, 8 }) |cpus, expected|
        try std.testing.expectEqual(expected, Jobs.forCpuCount(cpus));
    try std.testing.expectEqual(@as(usize, 256), (Jobs{ .count = 256 }).resolve());
}

test "frontend jobs parse automatic and explicit execution policies" {
    try std.testing.expectEqual(Jobs.auto, try Jobs.parse("auto"));
    try std.testing.expectEqual(@as(usize, 4), (try Jobs.parse("4")).count);
    for ([_][]const u8{ "0", "257", "-1", "many", "" }) |text|
        try std.testing.expectError(error.InvalidFrontendJobs, Jobs.parse(text));
}
