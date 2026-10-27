const support = @import("../../../support.zig");
const expectFrontendFailure = support.expectFrontendFailure;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/ownership/330X_caller_storage_dynamic_wrapper" {
    try expectFrontendFailure("tests/feature_tests/ownership/330X_caller_storage_dynamic_wrapper", "reference depends on a root that has ended");
}
