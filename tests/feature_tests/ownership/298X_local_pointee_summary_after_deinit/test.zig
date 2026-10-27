const support = @import("../../../support.zig");
const buildExpectFail = support.buildExpectFail;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/ownership/298X_local_pointee_summary_after_deinit" {
    try buildExpectFail(
        "tests/feature_tests/ownership/298X_local_pointee_summary_after_deinit",
        "root that has ended",
    );
}
