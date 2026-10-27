const support = @import("../../../support.zig");
const buildExpectFail = support.buildExpectFail;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/ownership/330X_caller_storage_dynamic_wrapper" {
    try buildExpectFail("tests/feature_tests/ownership/330X_caller_storage_dynamic_wrapper", "reference depends on a root that has ended");
}
