const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpectFailure = support.runExpectFailure;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/types/90X_allocation_establishment_wrap" {
    const path = "tests/feature_tests/types/90X_allocation_establishment_wrap";
    try expectSuccessfulBuild(path);
    try runExpectFailure(path);
}
