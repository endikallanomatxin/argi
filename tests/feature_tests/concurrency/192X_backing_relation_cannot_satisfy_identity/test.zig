const support = @import("../../../support.zig");
pub const isolation: support.Isolation = .fixture;
test "192X_backing_relation_cannot_satisfy_identity" {
    try support.expectFrontendFailure("tests/feature_tests/concurrency/192X_backing_relation_cannot_satisfy_identity", "cannot prove refers_to");
}
