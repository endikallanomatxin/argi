const support = @import("../../../support.zig");
pub const isolation: support.Isolation = .fixture;
test "concurrency 93_delegated_receiver_factory" {
    const path = "tests/feature_tests/concurrency/93_delegated_receiver_factory";
    try support.expectSuccessfulBuild(path);
    try support.runExpect(path, 0);
}
