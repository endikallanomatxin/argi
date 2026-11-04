const support = @import("../../../support.zig");
pub const isolation: support.Isolation = .fixture;
test "concurrency 51X_captured_domain_wrong_resource" {
    try support.expectFrontendFailure("tests/feature_tests/concurrency/51X_captured_domain_wrong_resource", "memory access exceeds the declared reads/writes bounds");
}
