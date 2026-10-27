const support = @import("../../../support.zig");
const buildExpectFail = support.buildExpectFail;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/ownership/160X_opaque_read_generation_survives_double_wrapper" {
    try buildExpectFail(
        "tests/feature_tests/ownership/160X_opaque_read_generation_survives_double_wrapper",
        "reference depends on a root that has ended",
    );
}
