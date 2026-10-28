const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpect = support.runExpect;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/system/25_local_typed_reach_binding" {
    const test_path = "tests/feature_tests/system/25_local_typed_reach_binding";
    try expectSuccessfulBuild(test_path);
    try runExpect(test_path, 0);
}
