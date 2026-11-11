const support = @import("../../../support.zig");
pub const isolation: support.Isolation = .fixture;
test "207X_reference_retargeted_before_lending" {
    try support.expectFrontendFailure("tests/feature_tests/concurrency/207X_reference_retargeted_before_lending", "pending execution");
}
