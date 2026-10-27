const support = @import("../../../support.zig");
const buildExpectFail = support.buildExpectFail;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/types/264X_fallible_init_requires_outcome" {
    try buildExpectFail(
        "tests/feature_tests/types/264X_fallible_init_requires_outcome",
        "value was deinitialized",
    );
}
