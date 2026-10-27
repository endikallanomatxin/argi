const support = @import("../../../support.zig");
const buildExpectFail = support.buildExpectFail;

pub const isolation: support.Isolation = .exclusive;

test "feature_tests/execution/114X_generic_inaccessible_global" {
    try buildExpectFail("tests/feature_tests/execution/114X_generic_inaccessible_global", "unknown name 'foreign_value' in this scope");
}
