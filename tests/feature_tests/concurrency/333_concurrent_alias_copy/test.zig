const support = @import("../../../support.zig");

pub const isolation: support.Isolation = .fixture;

test "333_concurrent_alias_copy" {
    const path = "tests/feature_tests/concurrency/333_concurrent_alias_copy";
    try support.expectSuccessfulBuild(path);
    try support.runExpect(path, 0);
}
