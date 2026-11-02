const support = @import("../../../support.zig");
const expectFrontendFailure = support.expectFrontendFailure;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/ownership/302X_storage_capability_alias_inputs" {
    try expectFrontendFailure("tests/feature_tests/ownership/302X_storage_capability_alias_inputs", "more than once");
}
