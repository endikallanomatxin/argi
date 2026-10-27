const support = @import("../../../support.zig");
const expectFrontendFailure = support.expectFrontendFailure;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/types/270X_acquired_storage_inspected_alias_consumed" {
    try expectFrontendFailure("tests/feature_tests/types/270X_acquired_storage_inspected_alias_consumed", "already been consumed");
}
