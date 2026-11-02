const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpect = support.runExpect;

pub const isolation: support.Isolation = .fixture;

test "tests/feature_tests/polymorphism/313_abstract_input_choice_contract" {
    try expectSuccessfulBuild("tests/feature_tests/polymorphism/313_abstract_input_choice_contract");
    try runExpect("tests/feature_tests/polymorphism/313_abstract_input_choice_contract", 0);
}
