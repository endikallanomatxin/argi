const support = @import("../../../support.zig");

pub const isolation: support.Isolation = .fixture;

test "426_joined_virtual_access_guarantee" {
    const path = "tests/feature_tests/concurrency/426_joined_virtual_access_guarantee";
    try support.expectSuccessfulBuild(path);
    try support.runExpect(path, 0);
}
