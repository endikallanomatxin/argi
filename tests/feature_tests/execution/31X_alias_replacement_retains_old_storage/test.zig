const support = @import("../../../support.zig");
const buildExpectFail = support.buildExpectFail;
const vmExpect = support.vmExpect;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/execution/31X_alias_replacement_retains_old_storage" {
    try buildExpectFail("tests/feature_tests/execution/31X_alias_replacement_retains_old_storage", "reference depends on a root that has ended");
    try vmExpect("tests/feature_tests/execution/31X_alias_replacement_retains_old_storage", 1, "reference depends on a root that has ended");
}
