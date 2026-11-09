const support = @import("../../../support.zig");
pub const isolation: support.Isolation = .fixture;
test "202X_reference_retargeted_multiple_local_aliases" {
    try support.expectFrontendFailure("tests/feature_tests/concurrency/202X_reference_retargeted_multiple_local_aliases", "pending execution");
}
