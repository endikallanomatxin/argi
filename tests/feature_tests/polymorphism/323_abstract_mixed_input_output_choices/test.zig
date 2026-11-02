const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpect = support.runExpect;

pub const isolation: support.Isolation = .fixture;

test "tests/feature_tests/polymorphism/323_abstract_mixed_input_output_choices" {
    try expectSuccessfulBuild("tests/feature_tests/polymorphism/323_abstract_mixed_input_output_choices");
    try runExpect("tests/feature_tests/polymorphism/323_abstract_mixed_input_output_choices", 0);
}
