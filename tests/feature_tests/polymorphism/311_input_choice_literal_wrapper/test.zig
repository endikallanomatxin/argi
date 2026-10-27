const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpect = support.runExpect;

pub const isolation: support.Isolation = .fixture;

test "tests/feature_tests/polymorphism/311_input_choice_literal_wrapper" {
    try expectSuccessfulBuild("tests/feature_tests/polymorphism/311_input_choice_literal_wrapper");
    try runExpect("tests/feature_tests/polymorphism/311_input_choice_literal_wrapper", 0);
}
