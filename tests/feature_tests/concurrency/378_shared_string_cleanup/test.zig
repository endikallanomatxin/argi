const support = @import("../../../support.zig");

pub const isolation: support.Isolation = .fixture;

test "378_shared_string_cleanup" {
    const path = "tests/feature_tests/concurrency/378_shared_string_cleanup";
    try support.expectSuccessfulBuild(path);
    try support.runExpect(path, 0);
}
