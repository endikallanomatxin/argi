const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpect = support.runExpect;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/types/280_positional_type_arguments" {
    try expectSuccessfulBuild("tests/feature_tests/types/280_positional_type_arguments");
    try runExpect("tests/feature_tests/types/280_positional_type_arguments", 0);
}
