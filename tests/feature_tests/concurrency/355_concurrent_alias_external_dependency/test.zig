const support = @import("../../../support.zig");

pub const isolation: support.Isolation = .fixture;

test "355_concurrent_alias_external_dependency" {
    const path = "tests/feature_tests/concurrency/355_concurrent_alias_external_dependency";
    try support.expectSuccessfulBuild(path);
    try support.runExpect(path, 0);
}
