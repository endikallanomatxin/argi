const support = @import("../../../support.zig");
const buildExpectFail = support.buildExpectFail;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/ownership/299X_nullable_pointee_summary_read" {
    try buildExpectFail(
        "tests/feature_tests/ownership/299X_nullable_pointee_summary_read",
        "root that has ended",
    );
}
