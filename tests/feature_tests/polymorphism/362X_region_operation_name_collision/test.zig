const support = @import("../../../support.zig");
pub const isolation: support.Isolation = .fixture;
test "polymorphism 362X_region_operation_name_collision" {
    try support.expectFrontendFailure("tests/feature_tests/polymorphism/362X_region_operation_name_collision", "contract operations and regions require distinct names");
}
