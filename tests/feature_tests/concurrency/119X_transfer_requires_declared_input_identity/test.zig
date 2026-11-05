const support = @import("../../../support.zig");
pub const isolation: support.Isolation = .fixture;
test "concurrency 119X_transfer_requires_declared_input_identity" {
    try support.expectFrontendFailure("tests/feature_tests/concurrency/119X_transfer_requires_declared_input_identity", "cannot prove transfers");
}
