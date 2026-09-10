const std = @import("std");
const primitives = @import("primitives/schema.zig");

pub fn idFits(id: anytype, len: usize) bool {
    return @intFromEnum(id) < len;
}

pub fn optionalIdFits(id: anytype, len: usize) bool {
    return if (id) |value| idFits(value, len) else true;
}

pub fn rangeFits(range: anytype, len: usize) bool {
    const start: usize = range.start;
    const count: usize = range.len;
    return start <= len and count <= len - start;
}

pub fn stringFits(range: primitives.StringRange, strings: []const u8) bool {
    return range.start <= strings.len and range.len <= strings.len - range.start;
}

pub fn sourceFits(source: primitives.SourceRef, file_count: usize) bool {
    return source.file_index < file_count;
}

test "verification helpers reject overflowing ranges" {
    try std.testing.expect(rangeFits(.{ .start = @as(u32, 2), .len = @as(u32, 3) }, 5));
    try std.testing.expect(!rangeFits(.{ .start = @as(u32, 4), .len = @as(u32, 2) }, 5));
    try std.testing.expect(!rangeFits(.{ .start = std.math.maxInt(u32), .len = @as(u32, 2) }, 5));
}

test "verification helpers validate typed ids and strings" {
    const Id = enum(u32) { _ };
    try std.testing.expect(idFits(@as(Id, @enumFromInt(1)), 2));
    try std.testing.expect(!idFits(@as(Id, @enumFromInt(2)), 2));
    try std.testing.expect(stringFits(.{ .start = 1, .len = 2 }, "abcd"));
    try std.testing.expect(!stringFits(.{ .start = 3, .len = 2 }, "abcd"));
}
