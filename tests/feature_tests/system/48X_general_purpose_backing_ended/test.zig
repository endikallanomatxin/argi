const support = @import("../../../support.zig");
const expectFrontendFailure = support.expectFrontendFailure;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/system/48X_general_purpose_backing_ended" {
    try expectFrontendFailure("tests/feature_tests/system/48X_general_purpose_backing_ended", "reference depends on a root that has ended");
}
