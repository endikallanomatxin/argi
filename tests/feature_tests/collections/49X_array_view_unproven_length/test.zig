const support = @import("../../../support.zig");
const buildExpectFail = support.buildExpectFail;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/collections/49X_array_view_unproven_length" {
    try buildExpectFail(
        "tests/feature_tests/collections/49X_array_view_unproven_length",
        "no generic function named 'single_mutable_array_view' accepts arguments",
    );
}
