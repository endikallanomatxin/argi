const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpect = support.runExpect;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/types/237_choice_inequality_refines_remaining_payload" {
    const test_path = "tests/feature_tests/types/237_choice_inequality_refines_remaining_payload";
    try expectSuccessfulBuild(test_path);
    try runExpect(test_path, 0);
}
