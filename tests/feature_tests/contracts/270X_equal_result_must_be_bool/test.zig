const support = @import("../../../support.zig");
const expectFrontendFailure = support.expectFrontendFailure;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/contracts/270X_equal_result_must_be_bool" {
    try expectFrontendFailure("tests/feature_tests/contracts/270X_equal_result_must_be_bool", "Equal.equal must return exactly (.ok: Bool)");
}
