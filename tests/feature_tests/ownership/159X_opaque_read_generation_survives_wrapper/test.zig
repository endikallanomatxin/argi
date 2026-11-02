const support = @import("../../../support.zig");
const expectFrontendFailure = support.expectFrontendFailure;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/ownership/159X_opaque_read_generation_survives_wrapper" {
    try expectFrontendFailure(
        "tests/feature_tests/ownership/159X_opaque_read_generation_survives_wrapper",
        "reference depends on a root that has ended",
    );
}
