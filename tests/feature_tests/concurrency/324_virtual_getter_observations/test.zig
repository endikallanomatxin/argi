const support = @import("../../../support.zig");

pub const isolation: support.Isolation = .fixture;

test "successive virtual getter calls observe the target at each call" {
    const path = "tests/feature_tests/concurrency/324_virtual_getter_observations";
    try support.expectSuccessfulBuild(path);
    try support.runExpect(path, 0);
}
