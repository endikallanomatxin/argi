const support = @import("../../../support.zig");
const buildExpectFail = support.buildExpectFail;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/ownership/167X_stale_array_pointer_use_through_wrapper_fails" {
    try buildExpectFail(
        "tests/feature_tests/ownership/167X_stale_array_pointer_use_through_wrapper_fails",
        "reference depends on a root that has ended",
    );
}
