const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpect = support.runExpect;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/polymorphism/241_forwarded_output_preserves_selected_generation" {
    try expectSuccessfulBuild("tests/feature_tests/polymorphism/241_forwarded_output_preserves_selected_generation");
    try runExpect("tests/feature_tests/polymorphism/241_forwarded_output_preserves_selected_generation", 0);
}
