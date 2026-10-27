const support = @import("../../../support.zig");
const expectFrontendFailure = support.expectFrontendFailure;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/ownership/311X_storage_capability_internal_alias" {
    try expectFrontendFailure("tests/feature_tests/ownership/311X_storage_capability_internal_alias", "more than once");
}
