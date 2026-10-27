const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpect = support.runExpect;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/types/242_choice_move_preserves_known_variant" {
    const test_path = "tests/feature_tests/types/242_choice_move_preserves_known_variant";
    try expectSuccessfulBuild(test_path);
    try runExpect(test_path, 0);
}
