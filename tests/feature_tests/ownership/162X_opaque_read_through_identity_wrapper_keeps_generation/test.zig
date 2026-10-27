const support = @import("../../../support.zig");
const buildExpectFail = support.buildExpectFail;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/ownership/162X_opaque_read_through_identity_wrapper_keeps_generation" {
    try buildExpectFail(
        "tests/feature_tests/ownership/162X_opaque_read_through_identity_wrapper_keeps_generation",
        "reference depends on a root that has ended",
    );
}
