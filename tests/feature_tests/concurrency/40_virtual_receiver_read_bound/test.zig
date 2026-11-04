const support = @import("../../../support.zig");
pub const isolation: support.Isolation = .fixture;
test "concurrency 40_virtual_receiver_read_bound" {
    const path = "tests/feature_tests/concurrency/40_virtual_receiver_read_bound";
    try support.expectSuccessfulBuild(path);
    try support.runExpect(path, 0);
}
