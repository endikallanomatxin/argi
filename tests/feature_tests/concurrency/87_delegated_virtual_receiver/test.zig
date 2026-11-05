const support = @import("../../../support.zig");
pub const isolation: support.Isolation = .fixture;
test "concurrency 87_delegated_virtual_receiver" {
    const path = "tests/feature_tests/concurrency/87_delegated_virtual_receiver";
    try support.expectSuccessfulBuild(path);
    try support.runExpect(path, 0);
}
