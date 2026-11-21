const support = @import("../../../support.zig");

pub const isolation: support.Isolation = .fixture;

test "raw offsets from a dynamic row cannot lose stored reference lifetimes" {
    const path = "tests/feature_tests/concurrency/305X_nested_dynamic_offset_unverified_reference_contents";
    try support.expectFrontendFailure(path, "cannot establish reference-bearing element contents for this offset");
}
