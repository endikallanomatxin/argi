const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpect = support.runExpect;

pub const isolation: support.Isolation = .exclusive;

test "feature_tests/execution/95_partial_owner_allocated_cleanup" {
    try expectSuccessfulBuild("tests/feature_tests/execution/95_partial_owner_allocated_cleanup");
    try runExpect("tests/feature_tests/execution/95_partial_owner_allocated_cleanup", 42);
}
