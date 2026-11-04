const support = @import("../../../support.zig");
pub const isolation: support.Isolation = .fixture;
test "concurrency 52X_captured_domain_readonly_mapping" {
    try support.expectFrontendFailure("tests/feature_tests/concurrency/52X_captured_domain_readonly_mapping", "writes requires mutable storage or a mutable reference");
}
