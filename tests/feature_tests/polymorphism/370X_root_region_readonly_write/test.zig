const support = @import("../../../support.zig");
pub const isolation: support.Isolation = .fixture;
test "polymorphism 370X_root_region_readonly_write" {
    try support.expectFrontendFailure("tests/feature_tests/polymorphism/370X_root_region_readonly_write", "writes requires mutable storage");
}
