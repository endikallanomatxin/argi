const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpect = support.runExpect;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/contracts/107_shared_unary_selection" {
    const path = "tests/feature_tests/contracts/107_shared_unary_selection";
    try expectSuccessfulBuild(path);
    try runExpect(path, 0);
}
