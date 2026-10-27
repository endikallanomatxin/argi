const support = @import("../../../support.zig");
const expectFrontendFailure = support.expectFrontendFailure;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/ownership/93X_relocation_maybe_initialized_destination" {
    try expectFrontendFailure(
        "tests/feature_tests/ownership/93X_relocation_maybe_initialized_destination",
        "relocate destination may be initialized",
    );
}
