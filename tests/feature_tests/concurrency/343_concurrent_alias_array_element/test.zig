const support = @import("../../../support.zig");

pub const isolation: support.Isolation = .fixture;

test "343_concurrent_alias_array_element" {
    const path = "tests/feature_tests/concurrency/343_concurrent_alias_array_element";
    try support.expectSuccessfulBuild(path);
    try support.runExpect(path, 0);
}
