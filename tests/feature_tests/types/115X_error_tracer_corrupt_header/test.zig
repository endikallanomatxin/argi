const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpectFailure = support.runExpectFailure;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/types/115X_error_tracer_corrupt_header" {
    const path = "tests/feature_tests/types/115X_error_tracer_corrupt_header";
    try expectSuccessfulBuild(path);
    try runExpectFailure(path);
}
