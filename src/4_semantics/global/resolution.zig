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

    /// Only `not_applicable` permits the semantic router to try another
    /// resolver. `deferred` means that the current resolver owns the operation
    /// but is waiting for another semantic dependency to become available.
    pub fn allowsFallback(self: Result) bool {
        return self == .not_applicable;
    }

    pub fn isDeferred(self: Result) bool {
        return self == .deferred;
    }
};

test "resolution result represents resolver ownership explicitly" {
    const std = @import("std");
    try std.testing.expectEqual(Result.deferred, Result.fromBool(false));
    try std.testing.expectEqual(Result.resolved, Result.fromBool(true));
    try std.testing.expect(!Result.not_applicable.isResolved());
    try std.testing.expect(Result.not_applicable.allowsFallback());
    try std.testing.expect(!Result.deferred.allowsFallback());
    try std.testing.expect(!Result.resolved.allowsFallback());
    try std.testing.expect(Result.deferred.isDeferred());
}
