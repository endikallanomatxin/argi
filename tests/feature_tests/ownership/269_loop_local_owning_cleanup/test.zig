const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpect = support.runExpect;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/ownership/269_loop_local_owning_cleanup" {
    const test_path = "tests/feature_tests/ownership/269_loop_local_owning_cleanup";
    try expectSuccessfulBuild(test_path);
    try runExpect(test_path, 0);
}
