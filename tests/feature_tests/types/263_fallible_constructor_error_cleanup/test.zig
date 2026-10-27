const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpect = support.runExpect;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/types/263_fallible_constructor_error_cleanup" {
    const path = "tests/feature_tests/types/263_fallible_constructor_error_cleanup";
    try expectSuccessfulBuild(path);
    try runExpect(path, 0);
}
