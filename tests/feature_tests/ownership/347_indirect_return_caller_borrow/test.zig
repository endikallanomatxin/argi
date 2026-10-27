const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpect = support.runExpect;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/ownership/347_indirect_return_caller_borrow" {
    try expectSuccessfulBuild("tests/feature_tests/ownership/347_indirect_return_caller_borrow");
    try runExpect("tests/feature_tests/ownership/347_indirect_return_caller_borrow", 0);
}
