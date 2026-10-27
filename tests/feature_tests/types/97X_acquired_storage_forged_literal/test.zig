const support = @import("../../../support.zig");
const buildExpectFail = support.buildExpectFail;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/types/97X_acquired_storage_forged_literal" {
    try buildExpectFail("tests/feature_tests/types/97X_acquired_storage_forged_literal", "field '_address' is private to its module");
}
