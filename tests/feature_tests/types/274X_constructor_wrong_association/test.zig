const support = @import("../../../support.zig");
const buildExpectFail = support.buildExpectFail;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/types/274X_constructor_wrong_association" {
    try buildExpectFail("tests/feature_tests/types/274X_constructor_wrong_association", "Init.Result must be its participant type");
}
