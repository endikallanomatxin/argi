const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpect = support.runExpect;

pub const isolation: support.Isolation = .fixture;

test "tests/feature_tests/polymorphism/321_abstract_reference_input_entry_choice" {
    try expectSuccessfulBuild("tests/feature_tests/polymorphism/321_abstract_reference_input_entry_choice");
    try runExpect("tests/feature_tests/polymorphism/321_abstract_reference_input_entry_choice", 0);
}
