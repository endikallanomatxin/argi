const support = @import("../../../support.zig");
const expectFrontendFailure = support.expectFrontendFailure;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/system/83X_directory_after_cleanup" {
    try expectFrontendFailure("tests/feature_tests/system/83X_directory_after_cleanup", "root that has ended");
}
