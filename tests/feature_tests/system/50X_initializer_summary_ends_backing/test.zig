const support = @import("../../../support.zig");
const expectFrontendFailure = support.expectFrontendFailure;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/system/50X_initializer_summary_ends_backing" {
    try expectFrontendFailure("tests/feature_tests/system/50X_initializer_summary_ends_backing", "reference depends on a root that has ended");
}
