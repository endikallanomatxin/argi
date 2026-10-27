const support = @import("../../../support.zig");
const buildExpectFail = support.buildExpectFail;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/ownership/104X_safe_reference_restriction_relocated" {
    try buildExpectFail(
        "tests/feature_tests/ownership/104X_safe_reference_restriction_relocated",
        "reference depends on a root that has ended",
    );
}
