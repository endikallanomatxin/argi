const support = @import("../../../support.zig");
pub const isolation: support.Isolation = .fixture;
test "concurrency 56X_captured_mapping_intermediate_reference" {
    try support.expectFrontendFailure("tests/feature_tests/concurrency/56X_captured_mapping_intermediate_reference", "captured access mapping requires a concrete intermediate reference target");
}
