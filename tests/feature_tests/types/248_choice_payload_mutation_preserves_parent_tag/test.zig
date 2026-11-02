const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpect = support.runExpect;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/types/248_choice_payload_mutation_preserves_parent_tag" {
    const test_path = "tests/feature_tests/types/248_choice_payload_mutation_preserves_parent_tag";
    try expectSuccessfulBuild(test_path);
    try runExpect(test_path, 0);
}
