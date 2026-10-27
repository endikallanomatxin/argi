const support = @import("../../../support.zig");
const buildExpectFail = support.buildExpectFail;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/ownership/159X_opaque_read_generation_survives_wrapper" {
    try buildExpectFail(
        "tests/feature_tests/ownership/159X_opaque_read_generation_survives_wrapper",
        "reference depends on a root that has ended",
    );
}
