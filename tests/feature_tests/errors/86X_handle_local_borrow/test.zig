const support = @import("../../../support.zig");
const expectFrontendFailure = support.expectFrontendFailure;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/errors/86X_handle_local_borrow" {
    try expectFrontendFailure("tests/feature_tests/errors/86X_handle_local_borrow", "root that has ended");
}
