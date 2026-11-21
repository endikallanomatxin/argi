const support = @import("../../../support.zig");

pub const isolation: support.Isolation = .fixture;

test "raw offsets cannot discard tracked reference contents from alternative arrays" {
    const path = "tests/feature_tests/concurrency/306X_conditional_offset_unverified_reference_contents";
    try support.expectFrontendFailure(path, "cannot establish reference-bearing element contents for this offset");
}
