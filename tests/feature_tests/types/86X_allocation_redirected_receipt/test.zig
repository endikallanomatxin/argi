const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpectFailure = support.runExpectFailure;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/types/86X_allocation_redirected_receipt" {
    const path = "tests/feature_tests/types/86X_allocation_redirected_receipt";
    try expectSuccessfulBuild(path);
    try runExpectFailure(path);
}
