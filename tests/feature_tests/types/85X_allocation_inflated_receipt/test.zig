const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpectFailure = support.runExpectFailure;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/types/85X_allocation_inflated_receipt" {
    const path = "tests/feature_tests/types/85X_allocation_inflated_receipt";
    try expectSuccessfulBuild(path);
    try runExpectFailure(path);
}
