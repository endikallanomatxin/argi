const support = @import("../../../support.zig");

pub const isolation: support.Isolation = .fixture;

test "301X_dynamic_offset_unverified_reference_contents" {
    const path = "tests/feature_tests/concurrency/301X_dynamic_offset_unverified_reference_contents";
    try support.expectFrontendFailure(path, "cannot establish reference-bearing element contents for this offset");
}
