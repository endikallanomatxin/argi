const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpectFailure = support.runExpectFailure;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/collections/57X_empty_view_data" {
    const path = "tests/feature_tests/collections/57X_empty_view_data";
    try expectSuccessfulBuild(path);
    try runExpectFailure(path);
}
