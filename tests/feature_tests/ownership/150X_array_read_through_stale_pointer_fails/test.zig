const support = @import("../../../support.zig");
const buildExpectFail = support.buildExpectFail;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/ownership/150X_array_read_through_stale_pointer_fails" {
    try buildExpectFail(
        "tests/feature_tests/ownership/150X_array_read_through_stale_pointer_fails",
        "reference depends on a root that has ended",
    );
}
