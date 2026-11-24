const support = @import("../../../support.zig");

pub const isolation: support.Isolation = .fixture;

test "337_concurrent_alias_recovery" {
    const path = "tests/feature_tests/concurrency/337_concurrent_alias_recovery";
    try support.expectSuccessfulBuild(path);
    try support.runExpect(path, 0);
}
