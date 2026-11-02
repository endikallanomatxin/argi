const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpect = support.runExpect;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/ownership/300_opaque_scalar_borrow_cleanup" {
    const path = "tests/feature_tests/ownership/300_opaque_scalar_borrow_cleanup";
    try expectSuccessfulBuild(path);
    try runExpect(path, 0);
}
