const support = @import("../../../support.zig");
const expectFrontendFailure = support.expectFrontendFailure;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/ownership/194X_opaque_release_in_short_circuit_rhs_is_not_definite" {
    try expectFrontendFailure(
        "tests/feature_tests/ownership/194X_opaque_release_in_short_circuit_rhs_is_not_definite",
        "cannot end a root while opaque storage hides a dependency on it",
    );
}
