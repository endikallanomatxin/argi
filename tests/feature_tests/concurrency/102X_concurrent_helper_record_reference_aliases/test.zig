const support = @import("../../../support.zig");
pub const isolation: support.Isolation = .fixture;
test "concurrency 102X_concurrent_helper_record_reference_aliases" {
    try support.expectFrontendFailure("tests/feature_tests/concurrency/102X_concurrent_helper_record_reference_aliases", "concurrent access conflicts through aliased function inputs");
}
