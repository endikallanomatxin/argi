const support = @import("../../../support.zig");
const buildExpectFail = support.buildExpectFail;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/ownership/281X_fallible_copy_is_not_implicit" {
    try buildExpectFail(
        "tests/feature_tests/ownership/281X_fallible_copy_is_not_implicit",
        "type 'FallibleValue' cannot be copied implicitly",
    );
}
