const support = @import("../../../support.zig");
const buildExpectFail = support.buildExpectFail;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/ownership/105X_safe_reference_restriction_stale_after_reinitialize" {
    try buildExpectFail(
        "tests/feature_tests/ownership/105X_safe_reference_restriction_stale_after_reinitialize",
        "reference depends on a root that has ended",
    );
}
