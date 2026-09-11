pub const Result = enum(u2) {
    not_applicable,
    deferred,
    resolved,

    pub fn fromOptionalBool(value: ?bool) Result {
        return if (value) |done|
            if (done) .resolved else .deferred
        else
            .not_applicable;
    }

    pub fn isResolved(self: Result) bool {
        return self == .resolved;
    }
};

test "resolution result preserves legacy states" {
    const std = @import("std");
    try std.testing.expectEqual(Result.not_applicable, Result.fromOptionalBool(null));
    try std.testing.expectEqual(Result.deferred, Result.fromOptionalBool(false));
    try std.testing.expectEqual(Result.resolved, Result.fromOptionalBool(true));
}
