const support = @import("../../../support.zig");
const buildExpectFail = support.buildExpectFail;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/contracts/291X_generic_default_no_cached_inference" {
    try buildExpectFail("tests/feature_tests/contracts/291X_generic_default_no_cached_inference", "no generic function named 'identity'");
}
