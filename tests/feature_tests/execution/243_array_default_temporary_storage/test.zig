const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpect = support.runExpect;
const vmExpect = support.vmExpect;

pub const isolation: support.Isolation = .exclusive;

test "feature_tests/execution/243_array_default_temporary_storage" {
    try expectSuccessfulBuild("tests/feature_tests/execution/243_array_default_temporary_storage");
    try runExpect("tests/feature_tests/execution/243_array_default_temporary_storage", 42);
    try vmExpect("tests/feature_tests/execution/243_array_default_temporary_storage", 42, null);
}
