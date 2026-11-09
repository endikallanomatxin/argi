const support = @import("../../../support.zig");
pub const isolation: support.Isolation = .fixture;
test "199X_unwrap_reference_unknown_alternative" {
    const path = "tests/feature_tests/concurrency/199X_unwrap_reference_unknown_alternative";
    try support.expectFrontendFailure(path, "pending execution");
}
