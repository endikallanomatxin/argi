const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpect = support.runExpect;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/types/101_acquired_storage_failure_and_empty" {
    const path = "tests/feature_tests/types/101_acquired_storage_failure_and_empty";
    try expectSuccessfulBuild(path);
    try runExpect(path, 0);
}
