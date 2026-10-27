const support = @import("../../../support.zig");
const buildExpectFail = support.buildExpectFail;
const vmExpect = support.vmExpect;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/execution/219X_returned_reference_list_keeps_alias_stale" {
    try buildExpectFail("tests/feature_tests/execution/219X_returned_reference_list_keeps_alias_stale", "root that has ended");
    try vmExpect("tests/feature_tests/execution/219X_returned_reference_list_keeps_alias_stale", 1, "root that has ended");
}
