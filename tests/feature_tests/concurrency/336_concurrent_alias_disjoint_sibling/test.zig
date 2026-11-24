const support = @import("../../../support.zig");

pub const isolation: support.Isolation = .fixture;

test "336_concurrent_alias_disjoint_sibling" {
    const path = "tests/feature_tests/concurrency/336_concurrent_alias_disjoint_sibling";
    try support.expectSuccessfulBuild(path);
    try support.runExpect(path, 0);
}
