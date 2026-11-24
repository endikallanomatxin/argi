const support = @import("../../../support.zig");

pub const isolation: support.Isolation = .fixture;

test "344_concurrent_alias_sequential_mutation" {
    const path = "tests/feature_tests/concurrency/344_concurrent_alias_sequential_mutation";
    try support.expectSuccessfulBuild(path);
    try support.runExpect(path, 0);
}
