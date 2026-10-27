const support = @import("../../../support.zig");
const buildExpectFail = support.buildExpectFail;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/ownership/305X_storage_capability_recursive_reuse" {
    try buildExpectFail("tests/feature_tests/ownership/305X_storage_capability_recursive_reuse", "more than once");
}
