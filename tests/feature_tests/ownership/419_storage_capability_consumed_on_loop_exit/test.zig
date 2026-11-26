const support = @import("../../../support.zig");

pub const isolation: support.Isolation = .fixture;

test "feature_tests/ownership/419_storage_capability_consumed_on_loop_exit" {
    const path = "tests/feature_tests/ownership/419_storage_capability_consumed_on_loop_exit";
    try support.expectSuccessfulBuild(path);
    try support.runExpect(path, 0);
}
