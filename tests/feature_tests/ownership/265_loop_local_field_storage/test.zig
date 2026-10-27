const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpect = support.runExpect;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/ownership/265_loop_local_field_storage" {
    const test_path = "tests/feature_tests/ownership/265_loop_local_field_storage";
    try expectSuccessfulBuild(test_path);
    try runExpect(test_path, 0);
}
