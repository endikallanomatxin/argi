const support = @import("../../../support.zig");
pub const isolation: support.Isolation = .fixture;
test "concurrency 103X_concurrent_helper_union_aliases" {
    try support.expectFrontendFailure("tests/feature_tests/concurrency/103X_concurrent_helper_union_aliases", "concurrent access conflicts through aliased function inputs");
}
