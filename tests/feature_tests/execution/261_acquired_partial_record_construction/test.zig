const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpect = support.runExpect;
const vmExpect = support.vmExpect;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/execution/261_acquired_partial_record_construction" {
    try expectSuccessfulBuild("tests/feature_tests/execution/261_acquired_partial_record_construction");
    try runExpect("tests/feature_tests/execution/261_acquired_partial_record_construction", 42);
    try vmExpect("tests/feature_tests/execution/261_acquired_partial_record_construction", 42, null);
}
