const support = @import("../../../support.zig");
const expectFrontendFailure = support.expectFrontendFailure;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/ownership/298X_local_pointee_summary_after_deinit" {
    try expectFrontendFailure(
        "tests/feature_tests/ownership/298X_local_pointee_summary_after_deinit",
        "root that has ended",
    );
}
