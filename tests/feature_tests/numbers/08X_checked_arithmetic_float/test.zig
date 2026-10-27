const support = @import("../../../support.zig");
const buildExpectFail = support.buildExpectFail;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/numbers/08X_checked_arithmetic_float" {
    try buildExpectFail("tests/feature_tests/numbers/08X_checked_arithmetic_float", "does not satisfy contract constraint 'Int'");
}
