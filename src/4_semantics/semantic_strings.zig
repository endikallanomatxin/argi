const std = @import("std");

/// Every spelling in a file semantic artifact uses offsets into its one owned
/// byte store. Builders borrow the store; retained tables never keep pointers
/// into it, so growth and relocation cannot invalidate their names.
pub const StringRange = struct { start: u32, len: u32 };
pub const Error = std.mem.Allocator.Error || error{ModuleSemanticGraphTooLarge};

pub fn append(strings: *std.ArrayList(u8), allocator: std.mem.Allocator, value: []const u8) Error!StringRange {
    if (value.len > std.math.maxInt(u32) or strings.items.len > std.math.maxInt(u32) - value.len)
        return error.ModuleSemanticGraphTooLarge;
    const range: StringRange = .{ .start = @intCast(strings.items.len), .len = @intCast(value.len) };
    try strings.appendSlice(allocator, value);
    return range;
}
