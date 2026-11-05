const support = @import("../../../support.zig");
pub const isolation: support.Isolation = .fixture;
test "concurrency 104X_virtual_hides_concurrent_alias_obligation" {
    try support.expectFrontendFailure("tests/feature_tests/concurrency/104X_virtual_hides_concurrent_alias_obligation", "a caller-side storage alias obligation is not represented by this contract");
}
