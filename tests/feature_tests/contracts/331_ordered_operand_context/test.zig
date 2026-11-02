const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpect = support.runExpect;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/contracts/331_ordered_operand_context" {
    try expectSuccessfulBuild("tests/feature_tests/contracts/331_ordered_operand_context");
    try runExpect("tests/feature_tests/contracts/331_ordered_operand_context", 0);
}
