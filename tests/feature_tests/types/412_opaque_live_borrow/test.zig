const support = @import("../../../support.zig");
pub const isolation: support.Isolation = .fixture;
test "412_opaque_live_borrow" {
    const path = "tests/feature_tests/types/412_opaque_live_borrow";
    try support.expectSuccessfulBuild(path);
    try support.runExpect(path, 0);
}
