const support = @import("../../../support.zig");

pub const isolation: support.Isolation = .fixture;

test "327_cleanup_after_both_join_orders" {
    const path = "tests/feature_tests/concurrency/327_cleanup_after_both_join_orders";
    try support.expectSuccessfulBuild(path);
    try support.runExpect(path, 0);
}
