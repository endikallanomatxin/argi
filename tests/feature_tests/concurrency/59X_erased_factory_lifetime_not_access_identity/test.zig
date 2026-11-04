const support = @import("../../../support.zig");
pub const isolation: support.Isolation = .fixture;
test "concurrency 59X_erased_factory_lifetime_not_access_identity" {
    try support.expectFrontendFailure("tests/feature_tests/concurrency/59X_erased_factory_lifetime_not_access_identity", "returning mapped Virtual storage requires transfers or refers_to");
}
