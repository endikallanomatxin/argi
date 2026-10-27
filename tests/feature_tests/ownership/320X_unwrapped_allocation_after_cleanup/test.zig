const support = @import("../../../support.zig");
const expectFrontendFailure = support.expectFrontendFailure;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/ownership/320X_unwrapped_allocation_after_cleanup" {
    try expectFrontendFailure("tests/feature_tests/ownership/320X_unwrapped_allocation_after_cleanup", "root that has ended");
}
