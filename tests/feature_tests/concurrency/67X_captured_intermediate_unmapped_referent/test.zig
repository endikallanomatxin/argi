const support = @import("../../../support.zig");
pub const isolation: support.Isolation = .fixture;
test "concurrency 67X_captured_intermediate_unmapped_referent" {
    try support.expectFrontendFailure("tests/feature_tests/concurrency/67X_captured_intermediate_unmapped_referent", "memory access exceeds the declared reads/writes bounds");
}
