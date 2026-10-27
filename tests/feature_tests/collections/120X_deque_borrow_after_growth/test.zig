const support = @import("../../../support.zig");
const expectFrontendFailure = support.expectFrontendFailure;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/collections/120X_deque_borrow_after_growth" {
    try expectFrontendFailure("tests/feature_tests/collections/120X_deque_borrow_after_growth", "root that has ended");
}
