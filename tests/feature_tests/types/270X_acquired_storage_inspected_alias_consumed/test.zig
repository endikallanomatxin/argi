const support = @import("../../../support.zig");
const buildExpectFail = support.buildExpectFail;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/types/270X_acquired_storage_inspected_alias_consumed" {
    try buildExpectFail("tests/feature_tests/types/270X_acquired_storage_inspected_alias_consumed", "already been consumed");
}
