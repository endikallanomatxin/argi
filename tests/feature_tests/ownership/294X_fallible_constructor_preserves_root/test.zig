const support = @import("../../../support.zig");
const expectFrontendFailure = support.expectFrontendFailure;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/ownership/294X_fallible_constructor_preserves_root" {
    try expectFrontendFailure(
        "tests/feature_tests/ownership/294X_fallible_constructor_preserves_root",
        "reference depends on a root that has ended",
    );
}

test "tests/feature_tests/ownership/294X_fallible_constructor_preserves_root wrapper parity" {
    try support.expectSafetyWrapperParity("tests/feature_tests/ownership/294X_fallible_constructor_preserves_root", "reference depends on a root that has ended");
}
