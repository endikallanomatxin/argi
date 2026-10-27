const support = @import("../../../support.zig");
const expectFrontendFailure = support.expectFrontendFailure;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/ownership/286X_uninitialized_allocation_read" {
    try expectFrontendFailure(
        "tests/feature_tests/ownership/286X_uninitialized_allocation_read",
        "is not dereferenceable; expected '&T' or '$&T'",
    );
}
