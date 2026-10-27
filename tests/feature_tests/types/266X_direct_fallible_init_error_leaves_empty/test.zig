const support = @import("../../../support.zig");
const buildExpectFail = support.buildExpectFail;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/types/266X_direct_fallible_init_error_leaves_empty" {
    try buildExpectFail(
        "tests/feature_tests/types/266X_direct_fallible_init_error_leaves_empty",
        "value was deinitialized",
    );
}
