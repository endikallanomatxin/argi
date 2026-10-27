const support = @import("../../../support.zig");
const buildExpectFail = support.buildExpectFail;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/ownership/284X_integer_cannot_establish_any_reference" {
    try buildExpectFail(
        "tests/feature_tests/ownership/284X_integer_cannot_establish_any_reference",
        "no function named 'cast' exists",
    );
}
