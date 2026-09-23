pub const Result = enum(u2) {
    not_applicable,
    deferred,
    invalid,
    resolved,

    pub fn fromBool(value: bool) Result {
        return if (value) .resolved else .deferred;
    }

    pub fn isResolved(self: Result) bool {
        return self == .resolved;
    }

    pub fn isInvalid(self: Result) bool {
        return self == .invalid;
    }

    /// `not_applicable` is an internal strategy result: a composite operation
    /// owner (for example call or index resolution) may try its next strategy.
    /// At the GlobalSema boundary every PendingOperation has one stable owner;
    /// `deferred` means that owner is waiting for semantic dependencies,
    /// `invalid` means all required information is present but the operation is
    /// semantically impossible and awaits a source diagnostic, and `resolved`
    /// means it has completed the operation.
    pub fn allowsFallback(self: Result) bool {
        return self == .not_applicable;
    }

    pub fn isDeferred(self: Result) bool {
        return self == .deferred;
    }
};

test "resolution result represents strategy fallback explicitly" {
    const std = @import("std");
    try std.testing.expectEqual(Result.deferred, Result.fromBool(false));
    try std.testing.expectEqual(Result.resolved, Result.fromBool(true));
    try std.testing.expect(!Result.not_applicable.isResolved());
    try std.testing.expect(Result.not_applicable.allowsFallback());
    try std.testing.expect(!Result.deferred.allowsFallback());
    try std.testing.expect(!Result.invalid.allowsFallback());
    try std.testing.expect(!Result.resolved.allowsFallback());
    try std.testing.expect(Result.deferred.isDeferred());
    try std.testing.expect(Result.invalid.isInvalid());
}
