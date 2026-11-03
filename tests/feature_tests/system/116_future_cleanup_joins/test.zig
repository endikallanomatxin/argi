const support = @import("../../../support.zig");
pub const isolation: support.Isolation = .fixture;
test "dropping a moved future joins its worker before releasing storage" {
    const path = "tests/feature_tests/system/116_future_cleanup_joins";
    try support.expectSuccessfulBuild(path);
    try support.runExpect(path, 0);
}
