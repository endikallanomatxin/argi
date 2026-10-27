const support = @import("../../../support.zig");
const expectFrontendFailure = support.expectFrontendFailure;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/execution/99X_incomplete_nested_record" {
    try expectFrontendFailure("tests/feature_tests/execution/99X_incomplete_nested_record", "deinitialized");
}
