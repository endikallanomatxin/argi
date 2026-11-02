const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpect = support.runExpect;
const vmExpect = support.vmExpect;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/execution/113_generic_global_scope" {
    try expectSuccessfulBuild("tests/feature_tests/execution/113_generic_global_scope");
    try runExpect("tests/feature_tests/execution/113_generic_global_scope", 42);
    try vmExpect("tests/feature_tests/execution/113_generic_global_scope", 42, null);
}
