const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpect = support.runExpect;
const vmExpect = support.vmExpect;

pub const isolation: support.Isolation = .exclusive;

test "feature_tests/execution/161_partial_choice_cleanup" {
    try expectSuccessfulBuild("tests/feature_tests/execution/161_partial_choice_cleanup");
    try runExpect("tests/feature_tests/execution/161_partial_choice_cleanup", 42);
    try vmExpect("tests/feature_tests/execution/161_partial_choice_cleanup", 42, null);
}
