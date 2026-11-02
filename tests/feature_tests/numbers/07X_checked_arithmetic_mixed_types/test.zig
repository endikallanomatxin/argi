const support = @import("../../../support.zig");
const expectFrontendFailure = support.expectFrontendFailure;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/numbers/07X_checked_arithmetic_mixed_types" {
    try expectFrontendFailure("tests/feature_tests/numbers/07X_checked_arithmetic_mixed_types", "conflicting inferred generic parameters");
}
