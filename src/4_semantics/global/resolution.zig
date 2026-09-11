pub const Result = enum(u2) {
    not_applicable,
    deferred,
    resolved,

    pub fn fromBool(value: bool) Result {
        return if (value) .resolved else .deferred;
    }

    pub fn isResolved(self: Result) bool {
        return self == .resolved;
    }
};

test "resolution result represents resolver ownership explicitly" {
    const std = @import("std");
    try std.testing.expectEqual(Result.deferred, Result.fromBool(false));
    try std.testing.expectEqual(Result.resolved, Result.fromBool(true));
    try std.testing.expect(!Result.not_applicable.isResolved());
}
