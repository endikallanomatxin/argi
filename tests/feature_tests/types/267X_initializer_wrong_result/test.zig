const support = @import("../../../support.zig");
const expectFrontendFailure = support.expectFrontendFailure;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/types/267X_initializer_wrong_result" {
    try expectFrontendFailure(
        "tests/feature_tests/types/267X_initializer_wrong_result",
        "Init.Result must be its participant type",
    );
}
