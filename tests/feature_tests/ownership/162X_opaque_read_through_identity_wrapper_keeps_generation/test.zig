const support = @import("../../../support.zig");
const expectFrontendFailure = support.expectFrontendFailure;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/ownership/162X_opaque_read_through_identity_wrapper_keeps_generation" {
    try expectFrontendFailure(
        "tests/feature_tests/ownership/162X_opaque_read_through_identity_wrapper_keeps_generation",
        "reference depends on a root that has ended",
    );
}

test "tests/feature_tests/ownership/162X_opaque_read_through_identity_wrapper_keeps_generation wrapper parity" {
    try support.expectSafetyWrapperParity("tests/feature_tests/ownership/162X_opaque_read_through_identity_wrapper_keeps_generation", "reference depends on a root that has ended");
}
