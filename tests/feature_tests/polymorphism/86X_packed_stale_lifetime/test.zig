const support = @import("../../../support.zig");

pub const isolation: support.Isolation = .fixture;

test "packed reference cannot outlive its prepared owner" {
    try support.expectFrontendFailure("tests/feature_tests/polymorphism/86X_packed_stale_lifetime", "place rooted at 'prepared' is moved and cannot be used");
}
