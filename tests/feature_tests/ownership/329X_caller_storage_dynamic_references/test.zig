const support = @import("../../../support.zig");
const buildExpectFail = support.buildExpectFail;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/ownership/329X_caller_storage_dynamic_references" {
    try buildExpectFail("tests/feature_tests/ownership/329X_caller_storage_dynamic_references", "reference depends on a root that has ended");
}
