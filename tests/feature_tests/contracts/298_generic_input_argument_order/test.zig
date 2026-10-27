const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpect = support.runExpect;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/contracts/298_generic_input_argument_order" {
    try expectSuccessfulBuild("tests/feature_tests/contracts/298_generic_input_argument_order");
    try runExpect("tests/feature_tests/contracts/298_generic_input_argument_order", 0);
}
