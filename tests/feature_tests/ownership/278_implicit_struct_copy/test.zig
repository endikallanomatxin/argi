const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpect = support.runExpect;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/ownership/278_implicit_struct_copy" {
    const test_path = "tests/feature_tests/ownership/278_implicit_struct_copy";
    try expectSuccessfulBuild(test_path);
    try runExpect(test_path, 0);
}
