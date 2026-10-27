const support = @import("../../../support.zig");
const expectFrontendFailure = support.expectFrontendFailure;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/contracts/275X_scalar_arithmetic_external_override" {
    try expectFrontendFailure("tests/feature_tests/contracts/275X_scalar_arithmetic_external_override", "an implementation must belong to the contract module or a nominal participant module");
}
