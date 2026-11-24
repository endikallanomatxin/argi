const support = @import("../../../support.zig");

pub const isolation: support.Isolation = .fixture;

test "360_concurrent_alias_forwarded_execution" {
    const path = "tests/feature_tests/concurrency/360_concurrent_alias_forwarded_execution";
    try support.expectSuccessfulBuild(path);
    try support.runExpect(path, 0);
}
