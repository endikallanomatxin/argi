const support = @import("../../../support.zig");
const expectFrontendFailure = support.expectFrontendFailure;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/ownership/305X_storage_capability_recursive_reuse" {
    try expectFrontendFailure("tests/feature_tests/ownership/305X_storage_capability_recursive_reuse", "more than once");
}
