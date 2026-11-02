const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpectFailure = support.runExpectFailure;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/types/78X_reference_offset_addition_overflow" {
    const path = "tests/feature_tests/types/78X_reference_offset_addition_overflow";
    try expectSuccessfulBuild(path);
    try runExpectFailure(path);
}
