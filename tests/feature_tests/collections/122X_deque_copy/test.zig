const support = @import("../../../support.zig");
const expectFrontendFailure = support.expectFrontendFailure;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/collections/122X_deque_copy" {
    try expectFrontendFailure("tests/feature_tests/collections/122X_deque_copy", "cannot be copied implicitly");
}
