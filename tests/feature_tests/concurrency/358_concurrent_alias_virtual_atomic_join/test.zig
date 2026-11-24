const support = @import("../../../support.zig");

pub const isolation: support.Isolation = .fixture;

test "358_concurrent_alias_virtual_atomic_join" {
    const path = "tests/feature_tests/concurrency/358_concurrent_alias_virtual_atomic_join";
    try support.expectSuccessfulBuild(path);
    try support.runExpect(path, 0);
}
