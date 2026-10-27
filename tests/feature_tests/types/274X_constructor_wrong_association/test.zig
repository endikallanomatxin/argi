const support = @import("../../../support.zig");
const expectFrontendFailure = support.expectFrontendFailure;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/types/274X_constructor_wrong_association" {
    try expectFrontendFailure("tests/feature_tests/types/274X_constructor_wrong_association", "Init.Result must be its participant type");
}
