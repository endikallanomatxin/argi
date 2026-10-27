const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpect = support.runExpect;
const vmExpect = support.vmExpect;

pub const isolation: support.Isolation = .exclusive;

test "feature_tests/execution/231_partial_record_initialization" {
    try expectSuccessfulBuild("tests/feature_tests/execution/231_partial_record_initialization");
    try runExpect("tests/feature_tests/execution/231_partial_record_initialization", 42);
    try vmExpect("tests/feature_tests/execution/231_partial_record_initialization", 42, null);
}
