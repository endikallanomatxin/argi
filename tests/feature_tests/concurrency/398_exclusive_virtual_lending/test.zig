const support = @import("../../../support.zig");

pub const isolation: support.Isolation = .fixture;

test "398_exclusive_virtual_lending" {
    const path = "tests/feature_tests/concurrency/398_exclusive_virtual_lending";
    try support.expectSuccessfulBuild(path);
    try support.runExpect(path, 0);
}
