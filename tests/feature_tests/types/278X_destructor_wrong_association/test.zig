const support = @import("../../../support.zig");
const expectFrontendFailure = support.expectFrontendFailure;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/types/278X_destructor_wrong_association" {
    try expectFrontendFailure("tests/feature_tests/types/278X_destructor_wrong_association", "implementation operation has an incompatible input signature");
}
