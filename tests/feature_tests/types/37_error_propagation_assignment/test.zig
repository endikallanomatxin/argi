const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpect = support.runExpect;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/types/37_error_propagation_assignment" {
    const test_path = "tests/feature_tests/types/37_error_propagation_assignment";
    try expectSuccessfulBuild(test_path);
    try runExpect(test_path, 5);
}
