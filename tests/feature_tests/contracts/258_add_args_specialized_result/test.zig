const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpect = support.runExpect;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/contracts/258_add_args_specialized_result" {
    try expectSuccessfulBuild("tests/feature_tests/contracts/258_add_args_specialized_result");
    try runExpect("tests/feature_tests/contracts/258_add_args_specialized_result", 0);
}
