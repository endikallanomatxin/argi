const support = @import("../../../support.zig");
const buildExpectFail = support.buildExpectFail;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/numbers/07X_checked_arithmetic_mixed_types" {
    try buildExpectFail("tests/feature_tests/numbers/07X_checked_arithmetic_mixed_types", "conflicting inferred generic parameters");
}
