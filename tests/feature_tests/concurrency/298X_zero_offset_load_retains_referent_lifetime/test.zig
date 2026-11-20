const support = @import("../../../support.zig");

pub const isolation: support.Isolation = .fixture;

test "298X_zero_offset_load_retains_referent_lifetime" {
    const path = "tests/feature_tests/concurrency/298X_zero_offset_load_retains_referent_lifetime";
    try support.expectFrontendFailure(path, "reference depends on a root that has ended");
}
