const support = @import("../../../support.zig");
const buildExpectFail = support.buildExpectFail;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/types/262X_fallible_init_success_without_value" {
    try buildExpectFail(
        "tests/feature_tests/types/262X_fallible_init_success_without_value",
        "value was deinitialized",
    );
}
