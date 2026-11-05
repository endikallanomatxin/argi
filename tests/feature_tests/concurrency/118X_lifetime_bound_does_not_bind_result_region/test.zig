const support = @import("../../../support.zig");
pub const isolation: support.Isolation = .fixture;
test "concurrency 118X_lifetime_bound_does_not_bind_result_region" {
    try support.expectFrontendFailure("tests/feature_tests/concurrency/118X_lifetime_bound_does_not_bind_result_region", "returning mapped Virtual storage requires transfers or refers_to");
}
