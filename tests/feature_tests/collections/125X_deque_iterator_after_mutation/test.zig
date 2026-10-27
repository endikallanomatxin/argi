const support = @import("../../../support.zig");
const expectFrontendFailure = support.expectFrontendFailure;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/collections/125X_deque_iterator_after_mutation" {
    try expectFrontendFailure("tests/feature_tests/collections/125X_deque_iterator_after_mutation", "root that has ended");
}
