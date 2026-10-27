const support = @import("../../../support.zig");
const buildExpectFail = support.buildExpectFail;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/collections/47X_dynamic_array_private_literal" {
    try buildExpectFail(
        "tests/feature_tests/collections/47X_dynamic_array_private_literal",
        "field '_allocation' is private to its module",
    );
}
