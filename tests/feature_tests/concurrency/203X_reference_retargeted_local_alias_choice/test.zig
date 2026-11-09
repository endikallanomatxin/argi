const support = @import("../../../support.zig");
pub const isolation: support.Isolation = .fixture;
test "203X_reference_retargeted_local_alias_choice" {
    try support.expectFrontendFailure("tests/feature_tests/concurrency/203X_reference_retargeted_local_alias_choice", "pending execution");
}
