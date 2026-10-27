const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpect = support.runExpect;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/types/33_error_propagation_statement_void" {
    const test_path = "tests/feature_tests/types/33_error_propagation_statement_void";
    try expectSuccessfulBuild(test_path);
    try runExpect(test_path, 7);
}
