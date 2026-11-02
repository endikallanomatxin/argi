const support = @import("../../../support.zig");
const expectFrontendFailure = support.expectFrontendFailure;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/ownership/329X_caller_storage_dynamic_references" {
    try expectFrontendFailure("tests/feature_tests/ownership/329X_caller_storage_dynamic_references", "reference depends on a root that has ended");
}
