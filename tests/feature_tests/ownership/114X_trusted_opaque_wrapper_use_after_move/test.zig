const support = @import("../../../support.zig");
const expectFrontendFailure = support.expectFrontendFailure;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/ownership/114X_trusted_opaque_wrapper_use_after_move" {
    try expectFrontendFailure("tests/feature_tests/ownership/114X_trusted_opaque_wrapper_use_after_move", "binding 'value' was moved and cannot be used again");
}
