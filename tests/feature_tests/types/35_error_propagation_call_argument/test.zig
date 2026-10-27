const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpect = support.runExpect;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/types/35_error_propagation_call_argument" {
    const test_path = "tests/feature_tests/types/35_error_propagation_call_argument";
    try expectSuccessfulBuild(test_path);
    try runExpect(test_path, 6);
}
