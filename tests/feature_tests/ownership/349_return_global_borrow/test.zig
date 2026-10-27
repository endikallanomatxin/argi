const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpect = support.runExpect;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/ownership/349_return_global_borrow" {
    try expectSuccessfulBuild("tests/feature_tests/ownership/349_return_global_borrow");
    try runExpect("tests/feature_tests/ownership/349_return_global_borrow", 0);
}
