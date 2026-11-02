const support = @import("../../../support.zig");
const expectFrontendFailure = support.expectFrontendFailure;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/errors/82X_handle_duplicate_names" {
    try expectFrontendFailure("tests/feature_tests/errors/82X_handle_duplicate_names", "must have different names");
}
