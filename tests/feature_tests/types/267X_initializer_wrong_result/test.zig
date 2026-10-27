const support = @import("../../../support.zig");
const buildExpectFail = support.buildExpectFail;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/types/267X_initializer_wrong_result" {
    try buildExpectFail(
        "tests/feature_tests/types/267X_initializer_wrong_result",
        "Init.Result must be its participant type",
    );
}
