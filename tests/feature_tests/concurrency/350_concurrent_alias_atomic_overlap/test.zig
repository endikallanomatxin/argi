const support = @import("../../../support.zig");

pub const isolation: support.Isolation = .fixture;

test "350_concurrent_alias_atomic_overlap" {
    const path = "tests/feature_tests/concurrency/350_concurrent_alias_atomic_overlap";
    try support.expectSuccessfulBuild(path);
    try support.runExpect(path, 0);
}
