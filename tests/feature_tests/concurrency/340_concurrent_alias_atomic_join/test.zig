const support = @import("../../../support.zig");

pub const isolation: support.Isolation = .fixture;

test "340_concurrent_alias_atomic_join" {
    const path = "tests/feature_tests/concurrency/340_concurrent_alias_atomic_join";
    try support.expectSuccessfulBuild(path);
    try support.runExpect(path, 0);
}
