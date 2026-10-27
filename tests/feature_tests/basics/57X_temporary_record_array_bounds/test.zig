const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpectFailure = support.runExpectFailure;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/basics/57X_temporary_record_array_bounds" {
    const path = "tests/feature_tests/basics/57X_temporary_record_array_bounds";
    try expectSuccessfulBuild(path);
    try runExpectFailure(path);
}
