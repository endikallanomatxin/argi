const support = @import("../../../support.zig");
const expectFrontendFailure = support.expectFrontendFailure;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/ownership/304X_storage_capability_loop_reuse" {
    try expectFrontendFailure("tests/feature_tests/ownership/304X_storage_capability_loop_reuse", "more than once");
}
