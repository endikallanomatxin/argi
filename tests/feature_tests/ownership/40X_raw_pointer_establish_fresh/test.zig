const support = @import("../../../support.zig");
const expectFrontendFailure = support.expectFrontendFailure;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/ownership/40X_raw_pointer_establish_fresh" {
    try expectFrontendFailure("tests/feature_tests/ownership/40X_raw_pointer_establish_fresh", "no function named 'establish_fresh_reference' exists");
}
