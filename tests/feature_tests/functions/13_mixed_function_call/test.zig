const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpect = support.runExpect;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/functions/13_mixed_function_call" {
    const test_path = "tests/feature_tests/functions/13_mixed_function_call";
    try expectSuccessfulBuild(test_path);
    try runExpect(test_path, 42);
}
