const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpect = support.runExpect;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/ownership/121_trusted_opaque_drop_cleanup" {
    const test_path = "tests/feature_tests/ownership/121_trusted_opaque_drop_cleanup";
    try expectSuccessfulBuild(test_path);
    try runExpect(test_path, 0);
}
