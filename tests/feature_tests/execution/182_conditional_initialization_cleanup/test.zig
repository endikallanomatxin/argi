const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpect = support.runExpect;
const vmExpect = support.vmExpect;

pub const isolation: support.Isolation = .exclusive;

test "feature_tests/execution/182_conditional_initialization_cleanup" {
    try expectSuccessfulBuild("tests/feature_tests/execution/182_conditional_initialization_cleanup");
    try runExpect("tests/feature_tests/execution/182_conditional_initialization_cleanup", 42);
    try vmExpect("tests/feature_tests/execution/182_conditional_initialization_cleanup", 42, null);
}
