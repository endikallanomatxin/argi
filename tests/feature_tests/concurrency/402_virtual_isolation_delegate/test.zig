const support = @import("../../../support.zig");

pub const isolation: support.Isolation = .fixture;

test "402_virtual_isolation_delegate" {
    const path = "tests/feature_tests/concurrency/402_virtual_isolation_delegate";
    try support.expectSuccessfulBuild(path);
    try support.runExpect(path, 0);
}
