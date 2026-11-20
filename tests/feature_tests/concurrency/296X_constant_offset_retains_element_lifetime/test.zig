const support = @import("../../../support.zig");

pub const isolation: support.Isolation = .fixture;

test "296X_constant_offset_retains_element_lifetime" {
    const path = "tests/feature_tests/concurrency/296X_constant_offset_retains_element_lifetime";
    try support.expectFrontendFailure(path, "reference depends on a root that has ended");
}
