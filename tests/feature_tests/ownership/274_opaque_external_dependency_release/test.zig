const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpect = support.runExpect;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/ownership/274_opaque_external_dependency_release" {
    const test_path = "tests/feature_tests/ownership/274_opaque_external_dependency_release";
    try expectSuccessfulBuild(test_path);
    try runExpect(test_path, 0);
}
