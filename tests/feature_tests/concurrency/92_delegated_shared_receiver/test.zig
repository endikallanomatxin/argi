const support = @import("../../../support.zig");
pub const isolation: support.Isolation = .fixture;
test "concurrency 92_delegated_shared_receiver" {
    const path = "tests/feature_tests/concurrency/92_delegated_shared_receiver";
    try support.expectSuccessfulBuild(path);
    try support.runExpect(path, 0);
}
