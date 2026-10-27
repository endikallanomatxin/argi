const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpect = support.runExpect;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/functions/01_function_calling" {
    const test_path = "tests/feature_tests/functions/01_function_calling";
    try expectSuccessfulBuild(test_path);
    try runExpect(test_path, 42);
}
