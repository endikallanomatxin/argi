const support = @import("../../../support.zig");
const expectFrontendFailure = support.expectFrontendFailure;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/system/58X_clock_missing_ffi" {
    try expectFrontendFailure("tests/feature_tests/system/58X_clock_missing_ffi", "construction arguments cannot infer a matching Init target");
}
