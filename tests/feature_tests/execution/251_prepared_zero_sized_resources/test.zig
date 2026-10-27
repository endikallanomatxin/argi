const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpect = support.runExpect;
const vmExpect = support.vmExpect;

pub const isolation: support.Isolation = .exclusive;

test "feature_tests/execution/251_prepared_zero_sized_resources" {
    try expectSuccessfulBuild("tests/feature_tests/execution/251_prepared_zero_sized_resources");
    try runExpect("tests/feature_tests/execution/251_prepared_zero_sized_resources", 42);
    try vmExpect("tests/feature_tests/execution/251_prepared_zero_sized_resources", 42, null);
}
