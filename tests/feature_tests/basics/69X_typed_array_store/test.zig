const support = @import("../../../support.zig");
const buildExpectFail = support.buildExpectFail;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/basics/69X_typed_array_store" {
    try buildExpectFail("tests/feature_tests/basics/69X_typed_array_store", "implicit numeric conversion is not supported");
}
