const support = @import("../../../support.zig");
const buildExpectFail = support.buildExpectFail;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/collections/51X_array_view_private_constructor" {
    try buildExpectFail(
        "tests/feature_tests/collections/51X_array_view_private_constructor",
        "field '_data' is private to its module",
    );
}
