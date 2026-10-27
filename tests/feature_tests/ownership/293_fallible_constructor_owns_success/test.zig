const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpect = support.runExpect;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/ownership/293_fallible_constructor_owns_success" {
    const test_path = "tests/feature_tests/ownership/293_fallible_constructor_owns_success";
    try expectSuccessfulBuild(test_path);
    try runExpect(test_path, 0);
}
