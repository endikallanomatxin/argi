const support = @import("../../../support.zig");
pub const isolation: support.Isolation = .fixture;
test "concurrency 57_bounded_virtual_receiver_forwarding" {
    const path = "tests/feature_tests/concurrency/57_bounded_virtual_receiver_forwarding";
    try support.expectSuccessfulBuild(path);
    try support.runExpect(path, 0);
}
