const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpect = support.runExpect;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/ownership/153_live_array_pointer_accesses" {
    const test_path = "tests/feature_tests/ownership/153_live_array_pointer_accesses";
    try expectSuccessfulBuild(test_path);
    try runExpect(test_path, 0);
}
