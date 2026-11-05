const support = @import("../../../support.zig");
pub const isolation: support.Isolation = .fixture;
test "polymorphism 369X_root_region_excludes_captured_referent" {
    try support.expectFrontendFailure("tests/feature_tests/polymorphism/369X_root_region_excludes_captured_referent", "memory access exceeds the declared reads/writes bounds");
}
