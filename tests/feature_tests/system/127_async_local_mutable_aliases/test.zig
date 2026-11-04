const support = @import("../../../support.zig");
pub const isolation: support.Isolation = .fixture;
test "access effects preserve worker-local mutable aliases" {
    const path = "tests/feature_tests/system/127_async_local_mutable_aliases";
    try support.expectSuccessfulBuild(path);
    try support.runExpect(path, 0);
}
