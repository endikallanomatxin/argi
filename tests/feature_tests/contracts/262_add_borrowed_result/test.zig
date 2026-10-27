const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpect = support.runExpect;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/contracts/262_add_borrowed_result" {
    try expectSuccessfulBuild("tests/feature_tests/contracts/262_add_borrowed_result");
    try runExpect("tests/feature_tests/contracts/262_add_borrowed_result", 0);
}
