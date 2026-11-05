const support = @import("../../../support.zig");
pub const isolation: support.Isolation = .fixture;
test "concurrency 61X_unknown_captured_region_may_alias" {
    try support.expectFrontendFailure("tests/feature_tests/concurrency/61X_unknown_captured_region_may_alias", "concurrent access conflicts through aliased function inputs");
}
