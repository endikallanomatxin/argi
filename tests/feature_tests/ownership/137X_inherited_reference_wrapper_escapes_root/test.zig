const support = @import("../../../support.zig");
const expectFrontendFailure = support.expectFrontendFailure;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/ownership/137X_inherited_reference_wrapper_escapes_root" {
    try expectFrontendFailure("tests/feature_tests/ownership/137X_inherited_reference_wrapper_escapes_root", "local storage generation");
}
