const support = @import("../../../support.zig");
pub const isolation: support.Isolation = .fixture;
test "161X_reference_forwarding_unknown_alternative" {
    const path = "tests/feature_tests/concurrency/161X_reference_forwarding_unknown_alternative";
    try support.expectFrontendFailure(path, "pending execution");
}
