const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpect = support.runExpect;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/ownership/233_opaque_effect_input_place_value_mark_empty" {
    const test_path = "tests/feature_tests/ownership/233_opaque_effect_input_place_value_mark_empty";
    try expectSuccessfulBuild(test_path);
    try runExpect(test_path, 0);
}
