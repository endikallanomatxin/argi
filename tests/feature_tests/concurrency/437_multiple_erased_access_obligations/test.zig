const support = @import("../../../support.zig");

pub const isolation: support.Isolation = .fixture;

test "437_multiple_erased_access_obligations" {
    const path = "tests/feature_tests/concurrency/437_multiple_erased_access_obligations";
    try support.expectSuccessfulBuild(path);
    try support.runExpect(path, 0);
}
