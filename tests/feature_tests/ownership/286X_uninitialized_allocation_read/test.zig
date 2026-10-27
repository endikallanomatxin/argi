const support = @import("../../../support.zig");
const buildExpectFail = support.buildExpectFail;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/ownership/286X_uninitialized_allocation_read" {
    try buildExpectFail(
        "tests/feature_tests/ownership/286X_uninitialized_allocation_read",
        "is not dereferenceable; expected '&T' or '$&T'",
    );
}
