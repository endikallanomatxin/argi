const support = @import("../../../support.zig");
const expectFrontendFailure = support.expectFrontendFailure;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/types/279X_destructor_unknown_type" {
    try expectFrontendFailure("tests/feature_tests/types/279X_destructor_unknown_type", "an implementation participant type is unknown or unresolved");
}
