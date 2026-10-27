const support = @import("../../../support.zig");
const buildExpectFail = support.buildExpectFail;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/collections/46X_fixed_array_constant_index_out_of_bounds" {
    try buildExpectFail(
        "tests/feature_tests/collections/46X_fixed_array_constant_index_out_of_bounds",
        "array index 2 is out of bounds for length 2",
    );
}
