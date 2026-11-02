const support = @import("../../../support.zig");
const expectFrontendFailure = support.expectFrontendFailure;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/ownership/310X_storage_capability_reference_input" {
    try expectFrontendFailure("tests/feature_tests/ownership/310X_storage_capability_reference_input", "already been consumed");
}
