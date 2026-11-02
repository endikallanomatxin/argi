const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpect = support.runExpect;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/ownership/289_aggregate_copy_after_field_replacement" {
    const test_path = "tests/feature_tests/ownership/289_aggregate_copy_after_field_replacement";
    try expectSuccessfulBuild(test_path);
    try runExpect(test_path, 0);
}
