const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpect = support.runExpect;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/contracts/285_write_owned_value_result" {
    try expectSuccessfulBuild("tests/feature_tests/contracts/285_write_owned_value_result");
    try runExpect("tests/feature_tests/contracts/285_write_owned_value_result", 0);
}
