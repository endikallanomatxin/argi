const support = @import("../../../support.zig");
const expectFrontendFailure = support.expectFrontendFailure;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/ownership/312X_storage_capability_nested_reference" {
    try expectFrontendFailure("tests/feature_tests/ownership/312X_storage_capability_nested_reference", "already been consumed");
}
