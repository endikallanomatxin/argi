const support = @import("../../../support.zig");

pub const isolation: support.Isolation = .fixture;

test "353_concurrent_alias_virtual_reader" {
    const path = "tests/feature_tests/concurrency/353_concurrent_alias_virtual_reader";
    try support.expectSuccessfulBuild(path);
    try support.runExpect(path, 0);
}
