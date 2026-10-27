const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpectFailure = support.runExpectFailure;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/types/94X_acquired_storage_extent" {
    const path = "tests/feature_tests/types/94X_acquired_storage_extent";
    try expectSuccessfulBuild(path);
    try runExpectFailure(path);
}
