const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpect = support.runExpect;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/ownership/122_trusted_opaque_relocate" {
    const test_path = "tests/feature_tests/ownership/122_trusted_opaque_relocate";
    try expectSuccessfulBuild(test_path);
    try runExpect(test_path, 0);
}
