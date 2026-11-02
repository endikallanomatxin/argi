const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpect = support.runExpect;

pub const isolation: support.Isolation = .fixture;

test "tests/feature_tests/polymorphism/327_abstract_input_guards_common_consumption" {
    try expectSuccessfulBuild("tests/feature_tests/polymorphism/327_abstract_input_guards_common_consumption");
    try runExpect("tests/feature_tests/polymorphism/327_abstract_input_guards_common_consumption", 0);
}
