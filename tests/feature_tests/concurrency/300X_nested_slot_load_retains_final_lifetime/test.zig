const support = @import("../../../support.zig");
pub const isolation: support.Isolation = .fixture;

test "300X_nested_slot_load_retains_final_lifetime" {
    const path = "tests/feature_tests/concurrency/300X_nested_slot_load_retains_final_lifetime";
    try support.expectFrontendFailure(path, "reference depends on a root that has ended");
}
