const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpectFailure = support.runExpectFailure;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/collections/38X_fixed_array_index_out_of_bounds" {
    const test_path = "tests/feature_tests/collections/38X_fixed_array_index_out_of_bounds";
    try expectSuccessfulBuild(test_path);
    try runExpectFailure(test_path);
}
