const support = @import("../../../support.zig");
const buildExpectFail = support.buildExpectFail;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/collections/55X_allocation_byte_helper_private" {
    try buildExpectFail(
        "tests/feature_tests/collections/55X_allocation_byte_helper_private",
        "no function named '_trusted_allocation_byte_rw' exists",
    );
}
