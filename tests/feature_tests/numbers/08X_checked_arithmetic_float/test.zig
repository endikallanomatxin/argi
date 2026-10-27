const support = @import("../../../support.zig");
const expectFrontendFailure = support.expectFrontendFailure;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/numbers/08X_checked_arithmetic_float" {
    try expectFrontendFailure("tests/feature_tests/numbers/08X_checked_arithmetic_float", "does not satisfy contract constraint 'Int'");
}
