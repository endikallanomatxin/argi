const support = @import("../../../support.zig");
pub const isolation: support.Isolation = .fixture;
test "concurrency 113X_composed_global_alias_access" {
    try support.expectFrontendFailure("tests/feature_tests/concurrency/113X_composed_global_alias_access", "unknown or global memory effects");
}
