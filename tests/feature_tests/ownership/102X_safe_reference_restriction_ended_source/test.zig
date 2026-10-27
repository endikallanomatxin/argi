const support = @import("../../../support.zig");
const buildExpectFail = support.buildExpectFail;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/ownership/102X_safe_reference_restriction_ended_source" {
    try buildExpectFail(
        "tests/feature_tests/ownership/102X_safe_reference_restriction_ended_source",
        "reference depends on a root that has ended",
    );
}
