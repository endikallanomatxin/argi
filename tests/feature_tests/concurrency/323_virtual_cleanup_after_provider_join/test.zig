const support = @import("../../../support.zig");

pub const isolation: support.Isolation = .fixture;

test "323_virtual_cleanup_after_provider_join" {
    const path = "tests/feature_tests/concurrency/323_virtual_cleanup_after_provider_join";
    try support.expectSuccessfulBuild(path);
    try support.runExpect(path, 0);
}
