const support = @import("../../../support.zig");
pub const isolation: support.Isolation = .fixture;
test "concurrency 11X_drop_other_reader" {
    try support.expectFrontendFailure("tests/feature_tests/concurrency/11X_drop_other_reader", "pending execution");
}
