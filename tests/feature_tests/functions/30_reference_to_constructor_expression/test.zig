const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpect = support.runExpect;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/functions/30_reference_to_constructor_expression" {
    try expectSuccessfulBuild("tests/feature_tests/functions/30_reference_to_constructor_expression");
    try runExpect("tests/feature_tests/functions/30_reference_to_constructor_expression", 0);
}
