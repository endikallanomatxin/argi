const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpectFailure = support.runExpectFailure;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/types/100X_acquired_page_storage_padding" {
    const path = "tests/feature_tests/types/100X_acquired_page_storage_padding";
    try expectSuccessfulBuild(path);
    try runExpectFailure(path);
}
