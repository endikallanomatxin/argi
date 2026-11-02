const std = @import("std");

/// A borrowed cancellation source. Callers retain the source until all work
/// using the token has joined; the predicate must support concurrent reads.
pub const Token = struct {
    context: ?*const anyopaque = null,
    is_cancelled: ?*const fn (?*const anyopaque) bool = null,

    pub fn check(self: Token) error{Cancelled}!void {
        if (self.is_cancelled) |cancelled| if (cancelled(self.context)) return error.Cancelled;
    }
};

test "cancellation is explicit and independent of allocation failure" {
    try (Token{}).check();
    const token: Token = .{ .is_cancelled = struct {
        fn cancelled(_: ?*const anyopaque) bool {
            return true;
        }
    }.cancelled };
    try std.testing.expectError(error.Cancelled, token.check());
}
